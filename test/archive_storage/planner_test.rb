# frozen_string_literal: true

require_relative "../test_helper"

class PlannerTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
    VersionedRecord.records.clear
    ScopedRecord.records.clear
    ModelFirstRecord.records.clear
  end

  def test_includes_versioned_files_when_policy_requests_versions
    VersionedRecord.records << VersionedRecord.new

    candidates = ArchiveStorage::Planner
                 .new(model: "VersionedRecord", mounted_as: :file)
                 .each_candidate
                 .to_a

    assert_equal ["uploads/versioned/report.txt", "uploads/versioned/thumb_report.txt"],
                 candidates.map(&:storage_key)
  end

  def test_archive_rule_scope_filters_planning_scope
    ScopedRecord.records << ScopedRecord.new(id: 1, archivable: true)
    ScopedRecord.records << ScopedRecord.new(id: 2, archivable: false)

    ArchiveStorage.configure do |config|
      config.mount "ScopedRecord", :file, uploader: "ScopedUploader"
    end

    candidates = ArchiveStorage::Planner
                 .new(uploader: "ScopedUploader")
                 .each_candidate
                 .to_a

    assert_equal ["uploads/scoped/1/report-1.txt"], candidates.map(&:storage_key)
  end

  def test_model_first_policy_registers_mount_and_filters_scope
    ModelFirstRecord.configure_archive_storage!
    ModelFirstRecord.records << ModelFirstRecord.new(id: 1, ready: true)
    ModelFirstRecord.records << ModelFirstRecord.new(id: 2, ready: false)

    candidates = ArchiveStorage::Planner
                 .new(model: "ModelFirstRecord", mounted_as: :file)
                 .each_candidate
                 .to_a

    assert_equal ["uploads/model_first/1/report-1.txt"], candidates.map(&:storage_key)
  end

  def test_max_byte_size_skips_large_files_during_planning
    ModelFirstRecord.configure_archive_storage_with_max!(3)
    ModelFirstRecord.records << ModelFirstRecord.new(id: 1, ready: true)
    ArchiveStorage.adapter(:hot).write("uploads/model_first/1/report-1.txt", "hello")

    candidates = ArchiveStorage::Planner
                 .new(model: "ModelFirstRecord", mounted_as: :file)
                 .each_candidate
                 .to_a

    assert_empty candidates
  end

  def test_max_byte_size_uses_current_storage_metadata
    ArchiveStorage.configure do |config|
      config.storage(:archive_002) { |storage| storage.provider = :memory }
    end
    ModelFirstRecord.configure_archive_storage_to_second_archive_with_max!(10)
    ModelFirstRecord.records << ModelFirstRecord.new(id: 1, ready: true)
    ArchiveStorage.adapter(:archive).write("uploads/model_first/1/report-1.txt", "hello")

    previous_registry = ArchiveStorage.registry
    ArchiveStorage.registry = Class.new do
      def current_storage_for(*)
        :archive
      end
    end.new

    candidates = ArchiveStorage::Planner
                 .new(model: "ModelFirstRecord", mounted_as: :file)
                 .each_candidate
                 .to_a

    assert_equal [:archive_002], candidates.map(&:target_storage)
  ensure
    ArchiveStorage.registry = previous_registry if previous_registry
  end
end
