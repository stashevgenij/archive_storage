# frozen_string_literal: true

require_relative "../test_helper"

class MigrationRateTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
  end

  def test_configures_files_per_scheduled_run
    ArchiveStorage.configure do |config|
      config.schedule :archive_documents,
                      cron: "0 0 * * *",
                      model: "ModelFirstRecord",
                      mounted_as: :file,
                      migration_rate: 10_000
    end

    rate = ArchiveStorage.configuration.schedules.first.migration_rate

    assert_equal 10_000, rate.max_files_per_run
  end

  def test_configures_schedule_without_rate
    ArchiveStorage.configure do |config|
      config.schedule :archive_documents,
                      cron: "0 0 * * *",
                      model: "ModelFirstRecord",
                      mounted_as: :file
    end

    assert_nil ArchiveStorage.configuration.schedules.first.migration_rate
  end

  def test_rejects_non_positive_limit
    assert_raises(ArgumentError) do
      ArchiveStorage.configure do |config|
        config.schedule :archive_documents,
                        cron: "0 0 * * *",
                        model: "ModelFirstRecord",
                        mounted_as: :file,
                        migration_rate: 0
      end
    end
  end
end
