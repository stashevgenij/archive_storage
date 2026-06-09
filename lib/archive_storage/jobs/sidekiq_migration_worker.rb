# frozen_string_literal: true

begin
  require "sidekiq"
rescue LoadError
  # Sidekiq is optional. This worker is only used when job_backend is :sidekiq.
end

require_relative "../migrator"

module ArchiveStorage
  module Jobs
    if defined?(::Sidekiq)
      class SidekiqMigrationWorker
        include ::Sidekiq::Worker

        sidekiq_options queue: ArchiveStorage.configuration.migration_queue.to_s

        def perform(file_record_id)
          record = ArchiveStorage.configuration.registry_class.find_by(id: file_record_id)
          return unless record

          begin
            Migrator.new.migrate_record!(record)
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
