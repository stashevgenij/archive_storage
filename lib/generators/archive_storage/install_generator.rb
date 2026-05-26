# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module ArchiveStorage
  class InstallGenerator < ::Rails::Generators::Base
    include ::Rails::Generators::Migration
    namespace "archive_storage:install"

    source_root File.expand_path("templates", __dir__)

    def copy_migration
      migration_template(
        "create_archive_storage_files.rb",
        "db/migrate/create_archive_storage_files.rb"
      )
    end

    def self.next_migration_number(dirname)
      if ::ActiveRecord::Base.timestamped_migrations
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      else
        "%.3d" % (current_migration_number(dirname) + 1)
      end
    end
  end
end
