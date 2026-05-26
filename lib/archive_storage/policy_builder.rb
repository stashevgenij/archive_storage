# frozen_string_literal: true

require_relative "policy"
require_relative "storage_rule"
require_relative "errors"

module ArchiveStorage
  class PolicyBuilder
    def self.build(&block)
      new.tap { |builder| builder.instance_eval(&block) }.tap(&:validate!).policy
    end

    attr_reader :policy

    def initialize
      @policy = Policy.new
    end

    def validate!
      raise ConfigurationError, "archive_storage requires a primary storage" unless policy.primary_storage_key
    end

    def primary(name)
      policy.primary_storage = StorageRule.new(:primary, name)
    end

    alias hot primary

    def warm(name, **options)
      rule(:warm, name, **options)
    end

    def archive(name, **options)
      rule(:archive, name, **options)
    end

    def storage(name, **options)
      rule(:storage, name, **options)
    end

    def rule(role, name, **options)
      policy.rules << StorageRule.new(
        role,
        name,
        after: options[:after],
        condition: options[:if],
        scope: options[:scope]
      )
    end

    def read_fallbacks(*names)
      policy.read_fallbacks = names.flatten.compact.map(&:to_sym)
    end

    def delete_source_after(verification: true, delay:)
      policy.delete_requires_verification = verification
      policy.delete_source_delay = delay
    end

    def include_versions(value = true)
      policy.include_versions = value
    end

    def versions(*names)
      policy.selected_versions = names.flatten.compact.map(&:to_sym)
    end

    def timestamp_attribute(name)
      policy.timestamp_attribute = name.to_sym
    end
  end
end
