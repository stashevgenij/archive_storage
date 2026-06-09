# frozen_string_literal: true

require_relative "storage_config"
require_relative "mount_config"
require_relative "schedule_config"
require_relative "cleanup_schedule_config"
require_relative "errors"

module ArchiveStorage
  class Configuration
    attr_accessor :migration_queue,
                  :schedule_queue,
                  :cleanup_queue,
                  :job_backend,
                  :verification_strategy,
                  :default_batch_size,
                  :default_cleanup_delay,
                  :enqueue_claim_ttl,
                  :max_attempts,
                  :retry_delays,
                  :delete_source_enabled,
                  :registry_class_name,
                  :fallback_on_read_errors

    attr_reader :verify_checksums
    attr_reader :storages, :mounts, :schedules

    def initialize
      @storages = {}
      @mounts = []
      @schedules = []
      @adapter_cache = {}
      @migration_queue = :default
      @schedule_queue = :default
      @cleanup_queue = :default
      @job_backend = :active_job
      @verification_strategy = :auto
      @verify_checksums = false
      @default_batch_size = 500
      @default_cleanup_delay = 7 * 24 * 60 * 60
      @enqueue_claim_ttl = 6 * 60 * 60
      @max_attempts = 5
      @retry_delays = [5 * 60, 30 * 60, 2 * 60 * 60, 6 * 60 * 60]
      @delete_source_enabled = false
      @registry_class_name = "ArchiveStorage::Models::FileRecord"
      @fallback_on_read_errors = [NotFoundError]
    end

    def verify_checksums=(value)
      @verify_checksums = value
      @verification_strategy = :checksum if value
    end

    def delete_source_enabled?
      delete_source_enabled.respond_to?(:call) ? !!delete_source_enabled.call : !!delete_source_enabled
    end

    def retry_delay_for(attempt)
      delays = Array(retry_delays)
      return 0 if delays.empty?

      delay = delays[[attempt.to_i - 1, 0].max] || delays.last
      delay.respond_to?(:call) ? delay.call(attempt).to_i : delay.to_i
    end

    def storage(name, &block)
      config = (@storages[name.to_sym] ||= StorageConfig.new(name))
      block.call(config) if block
      @adapter_cache.delete(name.to_sym)
      config
    end

    def storage!(name)
      @storages.fetch(name.to_sym) do
        raise ConfigurationError, "unknown archive storage #{name.inspect}"
      end
    end

    def adapter(name)
      @adapter_cache[name.to_sym] ||= build_adapter(storage!(name))
    end

    def mount(model, mounted_as, uploader: nil, policy: nil)
      MountConfig.new(model, mounted_as, uploader: uploader, policy: policy).tap do |mount|
        @mounts.reject! { |existing| existing.matches_model?(model, mounted_as) }
        @mounts << mount
      end
    end

    def find_mount(model, mounted_as)
      @mounts.find { |mount| mount.matches_model?(model, mounted_as) }
    end

    def schedule(name, cron:, model: nil, mounted_as: nil, uploader: nil, uploaders: nil, migration_rate: nil)
      ScheduleConfig.new(
        name,
        cron: cron,
        model: model,
        mounted_as: mounted_as,
        uploaders: Array(uploaders || uploader),
        migration_rate: migration_rate
      ).tap do |schedule|
        schedule.validate!
        @schedules << schedule
      end
    end

    def cleanup_schedule(name, cron:, limit: nil)
      CleanupScheduleConfig.new(name, cron: cron, limit: limit).tap do |schedule|
        schedule.validate!
        @schedules << schedule
      end
    end

    alias schedule_cleanup cleanup_schedule

    def registry_class
      registry_class_name.to_s.split("::").inject(Object) do |namespace, const_name|
        namespace.const_get(const_name)
      end
    end

    private

    def build_adapter(config)
      return config.adapter if config.adapter

      case config.provider.to_sym
      when :s3
        require_relative "adapters/s3"
        Adapters::S3.new(config)
      when :memory
        require_relative "adapters/memory"
        Adapters::Memory.new(config)
      when :filesystem, :file, :nfs
        require_relative "adapters/filesystem"
        Adapters::FileSystem.new(config)
      else
        raise ConfigurationError, "unsupported storage provider #{config.provider.inspect}"
      end
    end
  end
end
