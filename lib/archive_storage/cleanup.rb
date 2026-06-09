# frozen_string_literal: true

require_relative "migrator"

module ArchiveStorage
  CleanupResult = Struct.new(
    :deleted,
    :remaining_pending,
    keyword_init: true
  )

  class Cleanup
    def initialize(limit: nil, migrator: Migrator.new)
      @limit = normalize_limit(limit)
      @migrator = migrator
    end

    def call
      deleted = 0

      cleanup_scope.find_each do |file_record|
        deleted += 1 if migrator.cleanup_source!(file_record)
      end

      CleanupResult.new(
        deleted: deleted,
        remaining_pending: pending_cleanup_scope.count
      )
    end

    private

    attr_reader :limit, :migrator

    def cleanup_scope
      scope = pending_cleanup_scope
      limit ? scope.limit(limit) : scope
    end

    def pending_cleanup_scope
      ArchiveStorage.configuration.registry_class.pending_cleanup
    end

    def normalize_limit(value)
      return nil if value.nil? || value == ""

      Integer(value).tap do |limit|
        raise ArgumentError, "cleanup limit must be greater than zero" unless limit.positive?
      end
    end
  end
end
