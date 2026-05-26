# frozen_string_literal: true

require "archive_storage/planner"
require "archive_storage/migrator"
require "archive_storage/jobs/migration_job"

namespace :archive_storage do
  desc "Dry-run ArchiveStorage migration"
  task plan: :environment do
    planner = ArchiveStorage::Planner.new(
      uploader: ENV["UPLOADER"],
      model: ENV["MODEL"],
      mounted_as: ENV["MOUNT"],
      older_than: ENV["OLDER_THAN"],
      limit: ENV["LIMIT"],
      estimate_sizes: ENV.fetch("ESTIMATE_SIZES", "true") != "false"
    )

    puts planner.call.to_text
  end

  desc "Enqueue or run ArchiveStorage migration"
  task migrate: :environment do
    planner = ArchiveStorage::Planner.new(
      uploader: ENV["UPLOADER"],
      model: ENV["MODEL"],
      mounted_as: ENV["MOUNT"],
      older_than: ENV["OLDER_THAN"],
      limit: ENV["LIMIT"],
      estimate_sizes: true
    )

    inline = ENV.fetch("INLINE", "false") == "true"
    count = ArchiveStorage::Migrator
            .new(planner: planner)
            .enqueue_or_migrate!(inline: inline)

    puts "#{inline ? "Migrated" : "Enqueued"} #{count} files"
  end

  desc "Enqueue ArchiveStorage migration jobs"
  task enqueue: :migrate

  desc "Verify migrated ArchiveStorage files"
  task verify: :environment do
    scope = ArchiveStorage.configuration.registry_class.where.not(migrated_at: nil)
    count = 0

    scope.find_each do |file_record|
      ArchiveStorage::Migrator.new.verify_record!(file_record)
      count += 1
    end

    puts "Verified #{count} files"
  end

  desc "Delete verified source copies after cleanup delay"
  task cleanup_source: :environment do
    scope = ArchiveStorage.configuration.registry_class.pending_cleanup
    count = 0

    scope.find_each do |file_record|
      count += 1 if ArchiveStorage::Migrator.new.cleanup_source!(file_record)
    end

    puts "Deleted #{count} source copies"
  end

  desc "Show ArchiveStorage migration status"
  task status: :environment do
    records = ArchiveStorage.configuration.registry_class

    puts "ArchiveStorage Status"
    puts ""
    puts "Tracked:          #{records.count}"
    puts "Migrated:         #{records.where.not(migrated_at: nil).count}"
    puts "Verified:         #{records.where.not(verified_at: nil).count}"
    puts "Pending cleanup:  #{records.pending_cleanup.count}"
    puts "Source deleted:   #{records.where.not(source_deleted_at: nil).count}"
    puts "Failed:           #{records.where.not(last_error: [nil, ""]).count}"
  end
end
