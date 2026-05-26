# frozen_string_literal: true

require_relative "errors"
require_relative "migration_rate"

module ArchiveStorage
  class ScheduleConfig
    attr_reader :name, :cron, :model, :mounted_as, :uploaders, :migration_rate

    def initialize(name, cron:, model: nil, mounted_as: nil, uploaders: [], migration_rate: nil)
      @name = name.to_sym
      @cron = cron
      @model = model
      @mounted_as = mounted_as&.to_sym
      @uploaders = uploaders.flatten.compact.map(&:to_s)
      @migration_rate = MigrationRate.new(migration_rate) if migration_rate
    end

    def entry_name
      name
    end

    def job_arguments
      {}.tap do |args|
        if mount_schedule?
          args[:model] = model_name
          args[:mounted_as] = mounted_as.to_s
        else
          args[:uploaders] = uploaders
        end

        args[:migration_rate] = migration_rate.max_files_per_run if migration_rate
      end
    end

    def validate!
      raise ConfigurationError, "archive_storage schedule #{name.inspect} requires cron" if cron.nil? || cron == ""
      return if mount_schedule? || uploaders.any?

      raise ConfigurationError, "archive_storage schedule #{name.inspect} requires model/mounted_as or uploader"
    end

    def good_job_entry
      validate!

      {
        cron: cron,
        class: "ArchiveStorage::Jobs::QueueJob",
        set: { queue: ArchiveStorage.configuration.schedule_queue },
        args: [job_arguments]
      }
    end

    def sidekiq_cron_entry
      validate!

      {
        "cron" => cron,
        "class" => "ArchiveStorage::Jobs::SidekiqQueueWorker",
        "queue" => ArchiveStorage.configuration.schedule_queue.to_s,
        "args" => [stringify_keys(job_arguments)]
      }
    end

    private

    def mount_schedule?
      model && mounted_as
    end

    def model_name
      model.respond_to?(:name) ? model.name : model.to_s
    end

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
