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

    def target_storage_for(record, now: Time.now, byte_size: nil)
      target_rule_for(record, now: now, byte_size: byte_size)&.storage_key
    end

    def target_rule_for(record, now: Time.now, byte_size: nil)
      eligible_rules = rules.select do |rule|
        rule.eligible?(
          record,
          now: now,
          timestamp_attribute: timestamp_attribute,
          byte_size: byte_size
        )
      end

      eligible_rules.last
    end

    def rule_for_storage(storage_key)
      rules.reverse.find { |rule| rule.storage_key == storage_key.to_sym }
    end

    def requires_byte_size?
      rules.any?(&:max_byte_size?)
    end

    def requires_byte_size_for?(record, now: Time.now)
      rules.any? do |rule|
        rule.requires_byte_size_for?(
          record,
          now: now,
          timestamp_attribute: timestamp_attribute
        )
      end
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
