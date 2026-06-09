# frozen_string_literal: true

begin
  require "active_job"
rescue LoadError
  # ActiveJob is available in Rails apps.
end

require_relative "../migrator"

module ArchiveStorage
  module Jobs
    if defined?(::ActiveJob::Base)
      class MigrationJob < ::ActiveJob::Base
        queue_as do
          ArchiveStorage.configuration.migration_queue
        end

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
