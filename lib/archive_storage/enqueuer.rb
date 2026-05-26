# frozen_string_literal: true

module ArchiveStorage
  class Enqueuer
    def initialize(backend: ArchiveStorage.configuration.job_backend)
      @backend = backend.to_sym
    end

    def enqueue_migration(file_record_id)
      case backend
      when :inline
        require_relative "migrator"
        ArchiveStorage::Migrator.new.migrate_record!(ArchiveStorage.configuration.registry_class.find(file_record_id))
      when :active_job, :good_job
        require_relative "jobs/migration_job"
        Jobs::MigrationJob.perform_later(file_record_id)
      when :sidekiq
        require_relative "jobs/sidekiq_migration_worker"
        Jobs::SidekiqMigrationWorker.perform_async(file_record_id)
      else
        raise ConfigurationError, "unknown job backend #{backend.inspect}"
      end
    end

    private

    attr_reader :backend
  end
end
