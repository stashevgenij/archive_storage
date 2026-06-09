# frozen_string_literal: true

require_relative "../test_helper"

class RetryRegistryRecord
  ATTRS = [
    :record_type,
    :record_id,
    :mounted_as,
    :identifier,
    :storage_key,
    :uploader,
    :current_storage,
    :source_storage,
    :target_storage,
    :source_storage_key,
    :target_storage_key,
    :enqueued_at,
    :next_attempt_at,
    :terminal_failed_at,
    :source_delete_pending,
    :byte_size,
    :content_type,
    :migrated_at,
    :attempts
  ].freeze

  attr_accessor(*ATTRS)

  class << self
    attr_accessor :raise_unique_once
    attr_reader :find_calls, :save_calls, :stored

    def reset!
      @find_calls = 0
      @save_calls = 0
      @stored = nil
      @raise_unique_once = false
    end

    def find_or_initialize_by(identity)
      @find_calls += 1
      stored || new(identity)
    end

    def store!(attrs)
      @stored = new(attrs).tap(&:persist!)
    end

    def save_record!(record)
      @save_calls += 1

      if raise_unique_once && save_calls == 1
        @stored = record.persisted_copy
        raise ::ActiveRecord::RecordNotUnique, "duplicate identity"
      end

      record.persist!
      @stored = record
    end
  end

  def initialize(attrs = {})
    @persisted = false
    attrs.each { |key, value| public_send("#{key}=", value) }
  end

  def new_record?
    !@persisted
  end

  def save!
    self.class.save_record!(self)
  end

  def persist!
    @persisted = true
  end

  def persisted_copy
    self.class.new.tap do |copy|
      ATTRS.each { |attr| copy.public_send("#{attr}=", public_send(attr)) }
      copy.persist!
    end
  end
end

class RegistryTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
    RetryRegistryRecord.reset!
    ArchiveStorage.configuration.registry_class_name = "RetryRegistryRecord"
  end

  def test_claim_candidate_handles_unique_identity_race_without_duplicate_enqueue
    RetryRegistryRecord.raise_unique_once = true
    registry = Class.new(ArchiveStorage::Registry) do
      def available?
        true
      end
    end.new
    record = FakeModel.new(id: 1)
    candidate = ArchiveStorage::Candidate.new(
      record: record,
      mounted_as: :file,
      uploader: FakeUploader.new(record),
      identifier: "report.txt",
      storage_key: "uploads/1/report.txt",
      source_storage_key: "uploads/1/report.txt",
      target_storage_key: "uploads/1/report.txt",
      current_storage: :hot,
      target_storage: :archive
    )

    assert_nil registry.claim_candidate(candidate)
    assert_equal 2, RetryRegistryRecord.find_calls
    assert_equal 1, RetryRegistryRecord.save_calls
    assert RetryRegistryRecord.stored.enqueued_at
  end

  def test_claim_candidate_skips_records_that_reached_max_attempts
    ArchiveStorage.configuration.max_attempts = 3
    RetryRegistryRecord.store!(
      record_type: "FakeModel",
      record_id: 1,
      mounted_as: "file",
      identifier: "report.txt",
      storage_key: "uploads/1/report.txt",
      attempts: 3
    )

    assert_nil registry.claim_candidate(candidate)
    assert_equal 1, RetryRegistryRecord.find_calls
    assert_equal 0, RetryRegistryRecord.save_calls
  end

  def test_claim_candidate_waits_for_next_attempt_at
    RetryRegistryRecord.store!(
      record_type: "FakeModel",
      record_id: 1,
      mounted_as: "file",
      identifier: "report.txt",
      storage_key: "uploads/1/report.txt",
      attempts: 1,
      next_attempt_at: Time.now + 60
    )

    assert_nil registry.claim_candidate(candidate)
    assert_equal 0, RetryRegistryRecord.save_calls
  end

  def test_claim_candidate_allows_due_retry_and_clears_next_attempt
    RetryRegistryRecord.store!(
      record_type: "FakeModel",
      record_id: 1,
      mounted_as: "file",
      identifier: "report.txt",
      storage_key: "uploads/1/report.txt",
      attempts: 1,
      next_attempt_at: Time.now - 60
    )

    record = registry.claim_candidate(candidate)

    assert record
    assert_nil record.next_attempt_at
    assert record.enqueued_at
    assert_equal 1, RetryRegistryRecord.save_calls
  end

  private

  def registry
    @registry ||= Class.new(ArchiveStorage::Registry) do
      def available?
        true
      end
    end.new
  end

  def candidate
    record = FakeModel.new(id: 1)
    ArchiveStorage::Candidate.new(
      record: record,
      mounted_as: :file,
      uploader: FakeUploader.new(record),
      identifier: "report.txt",
      storage_key: "uploads/1/report.txt",
      source_storage_key: "uploads/1/report.txt",
      target_storage_key: "uploads/1/report.txt",
      current_storage: :hot,
      target_storage: :archive
    )
  end
end
