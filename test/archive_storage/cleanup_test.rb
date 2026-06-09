# frozen_string_literal: true

require "rake"
require_relative "../test_helper"

class CleanupRegistryRecord
  class << self
    def records
      @records ||= []
    end

    def reset!
      records.clear
    end

    def pending_cleanup
      CleanupRecordScope.new(
        records.select do |record|
          record.source_delete_pending &&
            record.source_deleted_at.nil? &&
            record.source_storage
        end
      )
    end
  end
end

class CleanupRecordScope
  def initialize(records)
    @records = records
  end

  def limit(value)
    self.class.new(@records.first(value))
  end

  def find_each
    @records.each { |record| yield record }
  end

  def count
    @records.count
  end
end

class CleanupTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
    CleanupRegistryRecord.reset!
    ArchiveStorage.configuration.registry_class_name = "CleanupRegistryRecord"
    ArchiveStorage.configuration.delete_source_enabled = true
    3.times do |index|
      key = "uploads/#{index}/report.txt"
      ArchiveStorage.adapter(:hot).write(key, "hello")
      CleanupRegistryRecord.records << FakeFileRecord.new(
        id: index + 1,
        storage_key: key,
        current_storage: "archive",
        source_storage: "hot",
        target_storage: "archive",
        verified_at: Time.now - 8 * 24 * 60 * 60,
        source_delete_pending: true
      )
    end
  end

  def test_cleanup_respects_limit
    result = ArchiveStorage::Cleanup.new(limit: 1).call

    assert_equal 1, result.deleted
    assert_equal 2, result.remaining_pending
  end

  def test_cleanup_job_runs_cleanup_with_limit
    result = ArchiveStorage::Jobs::CleanupJob.perform_now(limit: 2)

    assert_equal 2, result
    assert_equal 1, CleanupRegistryRecord.pending_cleanup.count
  end

  def test_cleanup_source_task_accepts_limit_and_prints_remaining_pending
    output = nil

    ENV["LIMIT"] = "1"
    begin
      with_archive_storage_rake_tasks do
        output = capture_io do
          Rake::Task["archive_storage:cleanup_source"].invoke
        end.first
      end
    ensure
      ENV.delete("LIMIT")
    end

    assert_includes output, "Deleted 1 source copies"
    assert_includes output, "Pending cleanup remaining: 2"
  end

  private

  def with_archive_storage_rake_tasks
    previous_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../../lib/archive_storage/tasks.rake", __dir__)
    yield
  ensure
    Rake.application = previous_application
  end
end
