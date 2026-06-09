# frozen_string_literal: true

require_relative "errors"
require_relative "enqueuer"
require_relative "planner"
require_relative "verifier"

module ArchiveStorage
  class Migrator
    def initialize(planner: nil)
      @planner = planner
    end

    def enqueue_or_migrate!(inline: false)
      count = 0

      planner.each_candidate do |candidate|
        file_record = ArchiveStorage.registry.claim_candidate(candidate)
        next unless file_record

        if inline
          migrate_record!(file_record)
        else
          Enqueuer.new.enqueue_migration(file_record.id)
        end

        count += 1
      end

      count
    end

    def migrate_record!(file_record)
      file_record.with_lock do
        return file_record if terminal_failed?(file_record)
        return mark_attempts_exhausted!(file_record) if attempts_exhausted?(file_record)

        source_storage = (file_record.source_storage || file_record.current_storage).to_sym
        target_storage = file_record.target_storage.to_sym
        source_key = file_record_source_key(file_record)
        target_key = file_record_target_key(file_record)

        return file_record if source_storage == target_storage && file_record.verified_at

        start_attrs = {
          migration_started_at: Time.now,
          attempts: file_record.attempts.to_i + 1,
          last_error: nil
        }
        start_attrs[:next_attempt_at] = nil if file_record.respond_to?(:next_attempt_at=)

        file_record.update!(start_attrs)

        source = ArchiveStorage.adapter(source_storage)
        target = ArchiveStorage.adapter(target_storage)

        validate_max_byte_size!(file_record, source, source_key, target_storage)

        target.copy_from(source, source_key, target_key)
        verification = Verifier.new.verify!(
          source_adapter: source,
          target_adapter: target,
          source_key: source_key,
          target_key: target_key
        )
        target_metadata = verification.target_metadata

        success_attrs = {
          current_storage: target_storage.to_s,
          source_storage: source_storage.to_s,
          target_storage: target_storage.to_s,
          storage_key: target_key,
          byte_size: target_metadata.byte_size,
          content_type: target_metadata.content_type,
          checksum: target_metadata.checksum || target_metadata.etag,
          migrated_at: Time.now,
          verified_at: Time.now,
          source_delete_pending: source_storage != target_storage,
          last_error: nil
        }
        success_attrs[:next_attempt_at] = nil if file_record.respond_to?(:next_attempt_at=)
        success_attrs[:terminal_failed_at] = nil if file_record.respond_to?(:terminal_failed_at=)

        file_record.update!(success_attrs)
      end

      file_record
    rescue StandardError => error
      safe_update_error(file_record, error)
      raise
    end

    def verify_record!(file_record)
      target_storage = (file_record.target_storage || file_record.current_storage).to_sym
      metadata = ArchiveStorage.adapter(target_storage).head(file_record.storage_key)

      file_record.update!(
        byte_size: metadata.byte_size,
        content_type: metadata.content_type,
        checksum: metadata.etag,
        verified_at: Time.now,
        last_error: nil
      )
    end

    def cleanup_source!(file_record)
      return false unless cleanup_ready?(file_record)

      source_storage = file_record.source_storage.to_sym
      ArchiveStorage.adapter(source_storage).delete(file_record_source_key(file_record))
      file_record.update!(source_deleted_at: Time.now, source_delete_pending: false)
      true
    end

    private

    attr_reader :planner

    def cleanup_ready?(file_record)
      return false unless ArchiveStorage.configuration.delete_source_enabled?
      return false unless file_record.source_storage
      return false if file_record.source_deleted_at

      policy = policy_for(file_record)
      policy_delay = cleanup_delay_for(file_record)
      requires_verification = policy.nil? || policy.delete_requires_verification
      verified = !file_record.verified_at.nil?
      reference_time = requires_verification ? file_record.verified_at : (file_record.verified_at || file_record.migrated_at)
      old_enough = reference_time && reference_time <= Time.now - policy_delay

      (!requires_verification || verified) && old_enough
    end

    def cleanup_delay_for(file_record)
      policy_for(file_record)&.delete_source_delay&.to_i ||
        ArchiveStorage.configuration.default_cleanup_delay
    end

    def policy_for(file_record)
      ArchiveStorage.policy_for_record(file_record.record_type, file_record.mounted_as)
    rescue StandardError
      nil
    end

    def validate_max_byte_size!(file_record, source_adapter, source_key, target_storage)
      rule = policy_for(file_record)&.rule_for_storage(target_storage)
      return unless rule&.max_byte_size?

      metadata = source_adapter.head(source_key)
      return if rule.byte_size_allowed?(metadata.byte_size)

      raise MaxByteSizeExceededError,
            "object #{source_key.inspect} is #{metadata.byte_size} bytes; max is #{rule.max_byte_size}"
    end

    def safe_update_error(file_record, error)
      return unless file_record.respond_to?(:update!)

      file_record.update!(failure_attributes(file_record, error))
    rescue StandardError
      nil
    end

    def failure_attributes(file_record, error)
      attrs = {
        last_error: "#{error.class}: #{error.message}"
      }
      attrs[:enqueued_at] = nil if file_record.respond_to?(:enqueued_at=)

      if terminal_error?(error) || attempts_exhausted?(file_record)
        attrs[:terminal_failed_at] = Time.now if file_record.respond_to?(:terminal_failed_at=)
        attrs[:next_attempt_at] = nil if file_record.respond_to?(:next_attempt_at=)
      elsif file_record.respond_to?(:next_attempt_at=)
        attrs[:next_attempt_at] = Time.now + ArchiveStorage.configuration.retry_delay_for(file_record.attempts.to_i)
        attrs[:terminal_failed_at] = nil if file_record.respond_to?(:terminal_failed_at=)
      end

      attrs
    end

    def terminal_error?(error)
      error.is_a?(MaxByteSizeExceededError)
    end

    def terminal_failed?(file_record)
      file_record.respond_to?(:terminal_failed_at) && file_record.terminal_failed_at
    end

    def attempts_exhausted?(file_record)
      max_attempts = ArchiveStorage.configuration.max_attempts
      return false unless max_attempts

      file_record.attempts.to_i >= max_attempts.to_i
    end

    def mark_attempts_exhausted!(file_record)
      return file_record unless file_record.respond_to?(:update!)
      return file_record unless file_record.respond_to?(:terminal_failed_at=)

      attrs = { terminal_failed_at: Time.now }
      attrs[:next_attempt_at] = nil if file_record.respond_to?(:next_attempt_at=)
      file_record.update!(attrs)
      file_record
    end

    def file_record_source_key(file_record)
      return file_record.source_storage_key if file_record.respond_to?(:source_storage_key) && file_record.source_storage_key

      file_record.storage_key
    end

    def file_record_target_key(file_record)
      return file_record.target_storage_key if file_record.respond_to?(:target_storage_key) && file_record.target_storage_key

      file_record.storage_key
    end
  end
end
