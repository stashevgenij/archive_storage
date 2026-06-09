# frozen_string_literal: true

require_relative "errors"

module ArchiveStorage
  class CleanupScheduleConfig
    attr_reader :name, :cron, :limit

    def initialize(name, cron:, limit: nil)
      @name = name.to_sym
      @cron = cron
      @limit = normalize_limit(limit)
    end

    def entry_name
      name
    end

    def job_arguments
      {}.tap do |args|
        args[:limit] = limit if limit
      end
    end

    def validate!
      raise ConfigurationError, "archive_storage cleanup schedule #{name.inspect} requires cron" if cron.nil? || cron == ""
    end

    def good_job_entry
      validate!

      {
        cron: cron,
        class: "ArchiveStorage::Jobs::CleanupJob",
        set: { queue: ArchiveStorage.configuration.cleanup_queue },
        args: [job_arguments]
      }
    end

    def sidekiq_cron_entry
      validate!

      {
        "cron" => cron,
        "class" => "ArchiveStorage::Jobs::SidekiqCleanupWorker",
        "queue" => ArchiveStorage.configuration.cleanup_queue.to_s,
        "args" => [stringify_keys(job_arguments)]
      }
    end

    private

    def normalize_limit(value)
      return nil if value.nil?

      Integer(value).tap do |limit|
        raise ArgumentError, "cleanup schedule limit must be greater than zero" unless limit.positive?
      end
    end

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
