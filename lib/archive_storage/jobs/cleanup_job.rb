# frozen_string_literal: true

begin
  require "active_job"
rescue LoadError
  # ActiveJob is available in Rails apps.
end

require_relative "../cleanup"

module ArchiveStorage
  module Jobs
    if defined?(::ActiveJob::Base)
      class CleanupJob < ::ActiveJob::Base
        queue_as do
          ArchiveStorage.configuration.cleanup_queue
        end

        def perform(options = {})
          options = options.to_h.transform_keys(&:to_sym)
          Cleanup.new(limit: options[:limit]).call.deleted
        end
      end
    end
  end
end
