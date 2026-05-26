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

          def verified?
            !!verified_at
          end
        end
      end
    end
end
