# frozen_string_literal: true

require_relative "../test_helper"

class PolicyTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
  end

  def test_selects_archive_when_record_is_old_and_condition_matches
    record = FakeModel.new(created_at: Time.now - 120 * 24 * 60 * 60)

    assert_equal :archive, FakeUploader.archive_storage_policy.target_storage_for(record)
  end

  def test_does_not_select_archive_for_young_record
    record = FakeModel.new(created_at: Time.now - 1 * 24 * 60 * 60)

    assert_nil FakeUploader.archive_storage_policy.target_storage_for(record)
  end

  def test_keeps_read_fallback_order
    assert_equal [:hot, :archive], FakeUploader.archive_storage_policy.read_fallbacks
  end

  def test_model_first_policy_is_resolved_from_model_and_mount
    ModelFirstRecord.configure_archive_storage!

    policy = ArchiveStorage.policy_for_mount(ModelFirstRecord, :file)

    assert_equal :archive, policy.target_storage_for(ModelFirstRecord.new(id: 1))
    assert_equal [:hot, :archive], policy.read_fallbacks
  end
end
