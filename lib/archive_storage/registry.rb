# frozen_string_literal: true

require_relative "errors"
require_relative "models/file_record"

module ArchiveStorage
  class Registry
    def available?
      defined?(::ActiveRecord::Base) &&
        ::ActiveRecord::Base.connected? &&
        record_class.table_exists?
    rescue StandardError
      false
    end

    def find_for_uploader(uploader, identifier:, storage_key:)
      return nil unless available?
      return nil unless uploader_identity_available?(uploader)

      record_class.find_by(
        identity_for_uploader(uploader, identifier: identifier, storage_key: storage_key)
      )
    end

    def current_storage_for(uploader, identifier:, storage_key:, default:)
      find_for_uploader(
        uploader,
        identifier: identifier,
        storage_key: storage_key
      )&.current_storage&.to_sym || default
    end

    def upsert_for_uploader(uploader, identifier:, storage_key:, current_storage:, metadata: {})
      return nil unless available?
      return nil unless uploader_identity_available?(uploader)

      with_unique_retry do
        record = record_class.find_or_initialize_by(
          identity_for_uploader(uploader, identifier: identifier, storage_key: storage_key)
        )

        record.uploader = uploader.class.name
        record.current_storage = current_storage.to_s
        record.byte_size ||= metadata[:byte_size]
        record.content_type ||= metadata[:content_type]
        record.checksum ||= metadata[:checksum]
        record.save!
        record
      end
    end

    def claim_candidate(candidate)
      raise RegistryUnavailableError, "archive_storage_files table is not available" unless available?

      with_unique_retry do
        record = record_class.find_or_initialize_by(
          identity_for_candidate(candidate)
        )
        return nil unless claimable?(record)

        record.uploader = candidate.uploader.class.name
        record.current_storage = candidate.current_storage.to_s
        record.source_storage = candidate.current_storage.to_s
        record.target_storage = candidate.target_storage.to_s
        record.source_storage_key = candidate.source_storage_key.to_s if record.respond_to?(:source_storage_key=)
        record.target_storage_key = candidate.target_storage_key.to_s if record.respond_to?(:target_storage_key=)
        record.enqueued_at = Time.now if record.respond_to?(:enqueued_at=)
        record.source_delete_pending = false if record.respond_to?(:source_delete_pending=) && record.new_record?
        record.byte_size ||= candidate.byte_size
        record.content_type ||= candidate.content_type
        record.save!
        record
      end
    end

    alias ensure_for_candidate claim_candidate

    private

    def record_class
      ArchiveStorage.configuration.registry_class
    end

    def claimable?(record)
      return false if record.respond_to?(:migrated_at) && record.migrated_at
      return true unless record.respond_to?(:enqueued_at)
      return true unless record.enqueued_at

      record.enqueued_at <= Time.now - ArchiveStorage.configuration.enqueue_claim_ttl
    end

    def uploader_identity_available?(uploader)
      uploader.respond_to?(:model) &&
        uploader.model &&
        uploader.model.respond_to?(:id) &&
        uploader.model.id &&
        uploader.respond_to?(:mounted_as) &&
        uploader.mounted_as
    end

    def identity_for_uploader(uploader, identifier:, storage_key:)
      {
        record_type: uploader.model.class.name,
        record_id: uploader.model.id,
        mounted_as: uploader.mounted_as.to_s,
        identifier: identifier.to_s,
        storage_key: storage_key.to_s
      }
    end

    def identity_for_candidate(candidate)
      {
        record_type: candidate.record.class.name,
        record_id: candidate.record.id,
        mounted_as: candidate.mounted_as.to_s,
        identifier: candidate.identifier.to_s,
        storage_key: candidate.storage_key.to_s
      }
    end

    def with_unique_retry
      yield
    rescue StandardError => error
      raise unless unique_violation?(error)

      yield
    end

    def unique_violation?(error)
      defined?(::ActiveRecord::RecordNotUnique) &&
        error.is_a?(::ActiveRecord::RecordNotUnique)
    end
  end
end
