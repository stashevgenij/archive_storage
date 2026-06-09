# frozen_string_literal: true

begin
  require "active_record"
rescue LoadError
  # ActiveRecord is loaded in Rails apps. The registry object handles absence.
end

module ArchiveStorage
    module Models
      if defined?(::ActiveRecord::Base)
        class FileRecord < ::ActiveRecord::Base
          self.table_name = "archive_storage_files"

          scope :verified, -> { where.not(verified_at: nil) }
          scope :pending_cleanup, -> {
            verified.where(source_delete_pending: true, source_deleted_at: nil).where.not(source_storage: nil)
          }
          scope :terminal_failed, -> { where.not(terminal_failed_at: nil) }
          scope :next_retry_scheduled, -> { where.not(next_attempt_at: nil).where(terminal_failed_at: nil) }

          def verified?
            !!verified_at
          end
        end
      end
    end
end
