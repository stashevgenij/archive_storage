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
  end
end
