# frozen_string_literal: true

require_relative "../test_helper"

class SchedulerTest < Minitest::Test
  include ArchiveStorageTestConfig

  FakeGoodJobConfig = Struct.new(:cron)
  FakeRailsConfig = Struct.new(:good_job)

  def setup
    reset_archive_storage!
    ArchiveStorage.configure do |config|
      config.schedule :archive_documents,
                      cron: "0 0 * * *",
                      model: "ModelFirstRecord",
                      mounted_as: :file
    end
  end

  def test_install_good_job_cron_merges_existing_entries
    existing = {
      daily_cleanup: {
        cron: "0 3 * * *",
        class: "CleanupJob"
      }
    }
    rails_config = FakeRailsConfig.new(FakeGoodJobConfig.new(existing))

    assert ArchiveStorage.install_good_job_cron!(rails_config: rails_config)

    cron = rails_config.good_job.cron
    assert_equal existing.fetch(:daily_cleanup), cron.fetch(:daily_cleanup)
    assert_equal "ArchiveStorage::Jobs::QueueJob",
                 cron.fetch(:archive_documents).fetch(:class)
  end

  def test_install_good_job_cron_does_nothing_without_entries
    ArchiveStorage.configuration.schedules.clear

    rails_config = FakeRailsConfig.new(FakeGoodJobConfig.new({}))

    refute ArchiveStorage.install_good_job_cron!(rails_config: rails_config)
    assert_empty rails_config.good_job.cron
  end

  def test_install_scheduled_jobs_uses_sidekiq_path_when_configured
    ArchiveStorage.configuration.job_backend = :sidekiq

    refute ArchiveStorage.install_scheduled_jobs!
  end
end
