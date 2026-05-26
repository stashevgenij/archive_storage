# frozen_string_literal: true

require "rails/railtie"

module ArchiveStorage
  class Railtie < ::Rails::Railtie
    initializer "archive_storage.active_record" do
      ActiveSupport.on_load(:active_record) do
        extend ArchiveStorage::Model
      end
    end

    initializer "archive_storage.install_scheduled_jobs" do |app|
      app.config.after_initialize do
        ArchiveStorage.install_scheduled_jobs!(rails_config: app.config)
      end
    end

    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end
  end
end
