# frozen_string_literal: true

module ArchiveStorage
  class << self
    def install_scheduled_jobs!(rails_config: nil)
      if configuration.job_backend.to_sym == :sidekiq
        install_sidekiq_schedules!
      else
        return false unless good_job_available?

        install_good_job_cron!(rails_config: rails_config)
      end
    end

    def install_good_job_cron!(rails_config: nil)
      entries = good_job_cron
      return false if entries.empty?

      config = rails_config || rails_application_config
      return false unless config&.respond_to?(:good_job)

      good_job_config = config.good_job
      good_job_config.cron = cron_hash(good_job_config.cron).merge(entries)
      true
    end

    def install_sidekiq_schedules!
      install_sidekiq_cron! || install_sidekiq_scheduler!
    end

    def install_sidekiq_cron!
      require "sidekiq"
      require "sidekiq-cron"
      require_relative "jobs/sidekiq_queue_worker"
      require_relative "jobs/sidekiq_cleanup_worker"

      ::Sidekiq.configure_server do |config|
        config.on(:startup) do
          entries = ArchiveStorage.sidekiq_cron
          ::Sidekiq::Cron::Job.load_from_hash(entries) if entries.any?
        end
      end

      true
    rescue LoadError
      false
    end

    def install_sidekiq_scheduler!
      require "sidekiq"
      require "sidekiq-scheduler"
      require_relative "jobs/sidekiq_queue_worker"
      require_relative "jobs/sidekiq_cleanup_worker"

      ::Sidekiq.configure_server do |config|
        config.on(:startup) do
          entries = ArchiveStorage.sidekiq_cron
          entries.each { |name, entry| ::Sidekiq.set_schedule(name, entry) }
          reload_sidekiq_scheduler if entries.any?
        end
      end

      true
    rescue LoadError
      false
    end

    private

    def cron_hash(value)
      return {} if value.nil?
      return value.to_h if value.respond_to?(:to_h)

      {}
    end

    def good_job_available?
      defined?(::GoodJob) || Gem.loaded_specs.key?("good_job")
    end

    def reload_sidekiq_scheduler
      if defined?(::SidekiqScheduler::Scheduler)
        ::SidekiqScheduler::Scheduler.instance.reload_schedule!
      elsif defined?(::Sidekiq::Scheduler) && ::Sidekiq::Scheduler.respond_to?(:reload_schedule!)
        ::Sidekiq::Scheduler.reload_schedule!
      end
    end

    def rails_application_config
      return nil unless defined?(::Rails) && ::Rails.respond_to?(:application)

      ::Rails.application&.config
    end
  end
end
