# frozen_string_literal: true

begin
  require "sidekiq"
rescue LoadError
  # Sidekiq is optional. This worker is only used when job_backend is :sidekiq.
end

require_relative "../cleanup"

module ArchiveStorage
  module Jobs
    if defined?(::Sidekiq)
      class SidekiqCleanupWorker
        include ::Sidekiq::Worker

        sidekiq_options queue: ArchiveStorage.configuration.cleanup_queue.to_s

        def perform(options = {})
          options = options.to_h.transform_keys(&:to_sym)
          Cleanup.new(limit: options[:limit]).call.deleted
        end
      end
    end
  end
end
