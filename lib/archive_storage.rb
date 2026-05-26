# frozen_string_literal: true

begin
  require "carrierwave"
rescue LoadError
  # ArchiveStorage can be loaded without CarrierWave. CarrierWave integration is optional at runtime.
end

require_relative "archive_storage/version"
require_relative "archive_storage/errors"
require_relative "archive_storage/configuration"
require_relative "archive_storage/policy_builder"
require_relative "archive_storage/model"
require_relative "archive_storage/registry"
require_relative "archive_storage/storage"
require_relative "archive_storage/planner"
require_relative "archive_storage/enqueuer"
require_relative "archive_storage/verifier"
require_relative "archive_storage/migrator"
require_relative "archive_storage/jobs/queue_job"
require_relative "archive_storage/jobs/migration_job"

module ArchiveStorage
  class << self
    attr_writer :configuration, :registry

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
      @registry = Registry.new
    end

    def adapter(name)
      configuration.adapter(name)
    end

    def registry
      @registry ||= Registry.new
    end

    def register_uploader(uploader_class)
      uploaders << uploader_class
    end

    def register_mount(model, mounted_as, uploader:, policy:)
      configuration.mount(model, mounted_as, uploader: uploader, policy: policy)
    end

    def wire_carrierwave_uploader!(uploader_class)
      return unless uploader_class

      uploader_class.include(CarrierWave) unless uploader_class < CarrierWave
      uploader_class.storage(:archive_storage) if uploader_class.respond_to?(:storage)
    end

    def policy_for_uploader(uploader)
      mount_policy_for_uploader(uploader) ||
        (uploader.class.archive_storage_policy if uploader.class.respond_to?(:archive_storage_policy))
    end

    def policy_for_mount(model, mounted_as)
      configuration.find_mount(model, mounted_as)&.policy ||
        model_policy(model, mounted_as)
    end

    def policy_for_record(record_type, mounted_as)
      policy_for_mount(record_type, mounted_as)
    end

    def uploaders
      @uploaders ||= []
    end

    def good_job_cron
      configuration.schedules.each_with_object({}) do |schedule, entries|
        entries[schedule.entry_name] = schedule.good_job_entry
      end
    end

    def sidekiq_cron
      configuration.schedules.each_with_object({}) do |schedule, entries|
        entries[schedule.entry_name.to_s] = schedule.sidekiq_cron_entry
      end
    end

    private

    def model_policy(model, mounted_as)
      model_class = model.is_a?(Class) ? model : constantize(model)
      return nil unless model_class.respond_to?(:archive_storage_policy_for)

      model_class.archive_storage_policy_for(mounted_as)
    rescue NameError
      nil
    end

    def mount_policy_for_uploader(uploader)
      return nil unless uploader.respond_to?(:model) && uploader.model
      return nil unless uploader.respond_to?(:mounted_as) && uploader.mounted_as

      policy_for_mount(uploader.model.class, uploader.mounted_as)
    end

    def constantize(value)
      value.to_s.split("::").inject(Object) { |namespace, name| namespace.const_get(name) }
    end
  end

  module CarrierWave
    def self.included(base)
      ArchiveStorage.register_uploader(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def archive_storage(&block)
        if block
          @archive_storage_policy = PolicyBuilder.build(&block)
        else
          archive_storage_policy
        end
      end

      def archive_storage_policy
        @archive_storage_policy ||
          (superclass.archive_storage_policy if superclass.respond_to?(:archive_storage_policy))
      end
    end
  end
end

if defined?(::CarrierWave) && ::CarrierWave.respond_to?(:configure)
  ::CarrierWave.configure do |config|
    if config.respond_to?(:storage_engines)
      config.storage_engines[:archive_storage] = "ArchiveStorage::Storage"
    end
  end
end

require_relative "archive_storage/scheduler"
require_relative "archive_storage/railtie" if defined?(::Rails::Railtie)
