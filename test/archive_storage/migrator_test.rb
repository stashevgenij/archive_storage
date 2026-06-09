# frozen_string_literal: true

require_relative "../test_helper"

class MigratorTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
  end

  def test_copies_verifies_and_switches_registry_record_to_target_storage
    hot = ArchiveStorage.adapter(:hot)
    hot.write("uploads/1/report.txt", "hello", content_type: "text/plain")

    record = FakeFileRecord.new(
      id: 1,
      storage_key: "uploads/1/report.txt",
      current_storage: "hot",
      source_storage: "hot",
      target_storage: "archive",
      attempts: 0
    )

    ArchiveStorage::Migrator.new.migrate_record!(record)

    assert_equal "archive", record.current_storage
    assert record.migrated_at
    assert record.verified_at
    assert_equal 5, record.byte_size
    assert_equal "hello", ArchiveStorage.adapter(:archive).read("uploads/1/report.txt")
    assert_equal "hello", hot.read("uploads/1/report.txt")
  end

  def test_cleanup_deletes_source_after_policy_delay
    ArchiveStorage.configuration.delete_source_enabled = true

    hot = ArchiveStorage.adapter(:hot)
    hot.write("uploads/1/report.txt", "hello", content_type: "text/plain")

    record = FakeFileRecord.new(
      uploader: "FakeUploader",
      storage_key: "uploads/1/report.txt",
      current_storage: "archive",
      source_storage: "hot",
      target_storage: "archive",
      verified_at: Time.now - 8 * 24 * 60 * 60
    )

    assert ArchiveStorage::Migrator.new.cleanup_source!(record)
    refute hot.exists?("uploads/1/report.txt")
    assert record.source_deleted_at
  end

  def test_cleanup_accepts_callable_delete_source_flag
    ArchiveStorage.configuration.delete_source_enabled = -> { true }

    hot = ArchiveStorage.adapter(:hot)
    hot.write("uploads/1/report.txt", "hello", content_type: "text/plain")

    record = FakeFileRecord.new(
      uploader: "FakeUploader",
      storage_key: "uploads/1/report.txt",
      current_storage: "archive",
      source_storage: "hot",
      target_storage: "archive",
      verified_at: Time.now - 8 * 24 * 60 * 60
    )

    assert ArchiveStorage::Migrator.new.cleanup_source!(record)
  end

  def test_migration_rejects_files_over_policy_max_byte_size
    ModelFirstRecord.configure_archive_storage_with_max!(3)
    hot = ArchiveStorage.adapter(:hot)
    hot.write("uploads/model_first/1/report-1.txt", "hello")

    record = FakeFileRecord.new(
      record_type: "ModelFirstRecord",
      record_id: 1,
      mounted_as: "file",
      uploader: "ModelFirstRecord::ArchiveStorageFileUploader",
      storage_key: "uploads/model_first/1/report-1.txt",
      current_storage: "hot",
      source_storage: "hot",
      target_storage: "archive",
      attempts: 0
    )

    assert_raises(ArchiveStorage::MaxByteSizeExceededError) do
      ArchiveStorage::Migrator.new.migrate_record!(record)
    end
    refute ArchiveStorage.adapter(:archive).exists?("uploads/model_first/1/report-1.txt")
    assert_equal 1, record.attempts
    assert_match "MaxByteSizeExceededError", record.last_error
    assert record.terminal_failed_at
    assert_nil record.next_attempt_at
  end

  def test_migration_error_sets_next_attempt_at_for_retry
    ArchiveStorage.configure do |config|
      config.retry_delays = [60]
      config.storage(:archive) { |storage| storage.adapter = FailingCopyAdapter.new }
    end
    ArchiveStorage.adapter(:hot).write("uploads/1/report.txt", "hello")
    record = FakeFileRecord.new(
      id: 1,
      storage_key: "uploads/1/report.txt",
      current_storage: "hot",
      source_storage: "hot",
      target_storage: "archive",
      attempts: 0,
      enqueued_at: Time.now
    )

    assert_raises(RuntimeError) do
      ArchiveStorage::Migrator.new.migrate_record!(record)
    end

    assert_equal 1, record.attempts
    assert_match "copy failed", record.last_error
    assert_nil record.enqueued_at
    assert record.next_attempt_at > Time.now
    refute record.terminal_failed_at
  end

  def test_migration_error_marks_terminal_after_max_attempts
    ArchiveStorage.configure do |config|
      config.max_attempts = 1
      config.retry_delays = [60]
      config.storage(:archive) { |storage| storage.adapter = FailingCopyAdapter.new }
    end
    ArchiveStorage.adapter(:hot).write("uploads/1/report.txt", "hello")
    record = FakeFileRecord.new(
      id: 1,
      storage_key: "uploads/1/report.txt",
      current_storage: "hot",
      source_storage: "hot",
      target_storage: "archive",
      attempts: 0,
      enqueued_at: Time.now
    )

    assert_raises(RuntimeError) do
      ArchiveStorage::Migrator.new.migrate_record!(record)
    end

    assert_equal 1, record.attempts
    assert record.terminal_failed_at
    assert_nil record.next_attempt_at
  end

  def test_existing_exhausted_attempts_are_marked_terminal
    ArchiveStorage.configuration.max_attempts = 1
    record = FakeFileRecord.new(
      id: 1,
      storage_key: "uploads/1/report.txt",
      current_storage: "hot",
      source_storage: "hot",
      target_storage: "archive",
      attempts: 1,
      next_attempt_at: Time.now - 60
    )

    ArchiveStorage::Migrator.new.migrate_record!(record)

    assert record.terminal_failed_at
    assert_nil record.next_attempt_at
  end

  def test_migration_job_uses_registry_backoff_without_backend_retry
    ArchiveStorage.configure do |config|
      config.registry_class_name = "MigrationJobRegistryRecord"
      config.retry_delays = [60]
      config.storage(:archive) { |storage| storage.adapter = FailingCopyAdapter.new }
    end
    ArchiveStorage.adapter(:hot).write("uploads/1/report.txt", "hello")
    record = FakeFileRecord.new(
      id: 1,
      storage_key: "uploads/1/report.txt",
      current_storage: "hot",
      source_storage: "hot",
      target_storage: "archive",
      attempts: 0,
      enqueued_at: Time.now
    )
    MigrationJobRegistryRecord.record = record

    result = ArchiveStorage::Jobs::MigrationJob.perform_now(1)

    assert_equal false, result
    assert_equal 1, record.attempts
    assert record.next_attempt_at
  ensure
    MigrationJobRegistryRecord.record = nil
  end

  class FailingCopyAdapter
    def copy_from(*)
      raise "copy failed"
    end
  end
end

class MigrationJobRegistryRecord
  class << self
    attr_accessor :record

    def find_by(id:)
      record if record&.id == id
    end
  end
end
