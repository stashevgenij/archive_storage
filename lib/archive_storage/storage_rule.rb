# frozen_string_literal: true

module ArchiveStorage
  class StorageRule
    attr_reader :role, :storage_key, :after, :condition, :scope

    def initialize(role, storage_key, after: nil, condition: nil, scope: nil)
      @role = role.to_sym
      @storage_key = storage_key.to_sym
      @after = after
      @condition = condition
      @scope = scope
    end

    def eligible?(record, now:, timestamp_attribute:)
      old_enough?(record, now: now, timestamp_attribute: timestamp_attribute) &&
        condition_matches?(record)
    end

    def scoped?
      !scope.nil?
    end

    def apply_scope(relation)
      case scope
      when Symbol, String
        relation.public_send(scope)
      when Proc
        scope.arity.zero? ? relation.instance_exec(&scope) : scope.call(relation)
      else
        relation.respond_to?(:merge) ? relation.merge(scope) : scope
      end
    end

    private

    def old_enough?(record, now:, timestamp_attribute:)
      return true unless after
      return false unless record

      timestamp = record.public_send(timestamp_attribute) if record.respond_to?(timestamp_attribute)
      return false unless timestamp

      timestamp <= now - seconds_after
    end

    def condition_matches?(record)
      return true unless condition

      condition.arity.zero? ? condition.call : condition.call(record)
    end

    def seconds_after
      after.respond_to?(:to_i) ? after.to_i : after
    end
  end
end
