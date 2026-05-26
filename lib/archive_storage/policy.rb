# frozen_string_literal: true

require_relative "storage_rule"

module ArchiveStorage
  class Policy
    attr_accessor :primary_storage,
                  :rules,
                  :read_fallbacks,
                  :delete_source_delay,
                  :delete_requires_verification,
                  :include_versions,
                  :selected_versions,
                  :timestamp_attribute

    def initialize
      @rules = []
      @read_fallbacks = []
      @delete_source_delay = nil
      @delete_requires_verification = true
      @include_versions = false
      @selected_versions = nil
      @timestamp_attribute = :created_at
    end

    def primary_storage_key
      primary_storage&.storage_key
    end

    def target_storage_for(record, now: Time.now)
      eligible_rules = rules.select do |rule|
        rule.eligible?(record, now: now, timestamp_attribute: timestamp_attribute)
      end

      eligible_rules.last&.storage_key
    end

    def apply_rule_scopes(scope)
      scoped_rules = rules.select(&:scoped?)
      return scope if scoped_rules.empty?

      relations = scoped_rules.map { |rule| rule.apply_scope(scope) }
      relations.reduce do |combined, relation|
        combined.respond_to?(:or) ? combined.or(relation) : combined
      end
    end
  end
end
