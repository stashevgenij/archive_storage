# frozen_string_literal: true

require_relative "../test_helper"

class ScheduleConfigTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
    configure_schedules!
  end

  def test_uploader_schedule_generates_good_job_entry
    entry = ArchiveStorage.good_job_cron.fetch(:archive_documents)

    assert_equal "0 0 * * *", entry.fetch(:cron)
    assert_equal "ArchiveStorage::Jobs::QueueJob", entry.fetch(:class)
    assert_equal [{ model: "ModelFirstRecord", mounted_as: "file", migration_rate: 10_000 }], entry.fetch(:args)
  end

  def test_configuration_can_define_multiple_schedules
    entry = ArchiveStorage.good_job_cron.fetch(:archive_documents_weekend)

    assert_equal "0 1 * * 6", entry.fetch(:cron)
    assert_equal [{ model: "ModelFirstRecord", mounted_as: "file" }], entry.fetch(:args)
  end

  def test_uploader_schedule_generates_sidekiq_cron_entry
    entry = ArchiveStorage.sidekiq_cron.fetch("archive_documents")

    assert_equal "0 0 * * *", entry.fetch("cron")
    assert_equal "ArchiveStorage::Jobs::SidekiqQueueWorker", entry.fetch("class")
    assert_equal "default", entry.fetch("queue")
    assert_equal [{ "model" => "ModelFirstRecord", "mounted_as" => "file", "migration_rate" => 10_000 }], entry.fetch("args")
  end

  def test_cleanup_schedule_generates_good_job_entry
    ArchiveStorage.configuration.cleanup_queue = :archive_cleanup
    ArchiveStorage.configure do |config|
      config.cleanup_schedule :archive_cleanup,
                              cron: "30 3 * * *",
                              limit: 2_000
    end

    entry = ArchiveStorage.good_job_cron.fetch(:archive_cleanup)

    assert_equal "30 3 * * *", entry.fetch(:cron)
    assert_equal "ArchiveStorage::Jobs::CleanupJob", entry.fetch(:class)
    assert_equal({ queue: :archive_cleanup }, entry.fetch(:set))
    assert_equal [{ limit: 2_000 }], entry.fetch(:args)
  end

  def test_cleanup_schedule_generates_sidekiq_cron_entry
    ArchiveStorage.configuration.cleanup_queue = :archive_cleanup
    ArchiveStorage.configure do |config|
      config.cleanup_schedule :archive_cleanup,
                              cron: "30 3 * * *",
                              limit: 2_000
    end

    entry = ArchiveStorage.sidekiq_cron.fetch("archive_cleanup")

    assert_equal "30 3 * * *", entry.fetch("cron")
    assert_equal "ArchiveStorage::Jobs::SidekiqCleanupWorker", entry.fetch("class")
    assert_equal "archive_cleanup", entry.fetch("queue")
    assert_equal [{ "limit" => 2_000 }], entry.fetch("args")
  end

  def test_configuration_requires_uploader
    assert_raises(ArchiveStorage::ConfigurationError) do
      ArchiveStorage.configure do |config|
        config.schedule :archive_documents, cron: "0 0 * * *"
      end
    end
  end

  private

  def configure_schedules!
    ArchiveStorage.configure do |config|
      config.schedule :archive_documents,
                      cron: "0 0 * * *",
                      model: "ModelFirstRecord",
                      mounted_as: :file,
                      migration_rate: 10_000

      config.schedule :archive_documents_weekend,
                      cron: "0 1 * * 6",
                      model: "ModelFirstRecord",
                      mounted_as: :file
    end
  end
end
