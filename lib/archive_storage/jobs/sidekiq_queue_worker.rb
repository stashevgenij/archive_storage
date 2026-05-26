# frozen_string_literal: true

begin
  require "sidekiq"
rescue LoadError
  # Sidekiq is optional. Require this file only in Sidekiq-backed apps.
end

require_relative "../errors"
require_relative "../migrator"
require_relative "../planner"

module ArchiveStorage
  module Jobs
    if defined?(::Sidekiq)
      class SidekiqQueueWorker
        include ::Sidekiq::Worker

        sidekiq_options queue: ArchiveStorage.configuration.schedule_queue.to_s

        def perform(options = {})
          options = symbolize_keys(options)
          remaining = migration_limit(options)
          total = 0

          planner_options(options).each do |planner_options|
            break if remaining && remaining <= 0

            planner = Planner.new(**planner_options.merge(limit: remaining))
            count = Migrator.new(planner: planner).enqueue_or_migrate!
            remaining -= count if remaining
            total += count
          end

          total
        end

        private

        def symbolize_keys(hash)
          hash.to_h.transform_keys(&:to_sym)
        end

        def scheduled_uploaders(options)
          Array(options[:uploaders] || options[:uploader]).flatten.compact.tap do |uploaders|
            raise ConfigurationError, "ArchiveStorage::Jobs::SidekiqQueueWorker requires uploader or uploaders" if uploaders.empty?
          end
        end

        def planner_options(options)
          if options[:model] && options[:mounted_as]
            [{ model: options[:model], mounted_as: options[:mounted_as] }]
          else
            scheduled_uploaders(options).map { |uploader| { uploader: uploader } }
          end
        end

        def migration_limit(options)
          limit = options[:migration_rate] || options[:limit]
          limit&.to_i
        end
      end
    end
  end
end
