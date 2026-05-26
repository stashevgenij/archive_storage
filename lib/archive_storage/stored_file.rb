# frozen_string_literal: true

require_relative "errors"

module ArchiveStorage
  class StoredFile
    attr_reader :uploader, :identifier, :storage_key

    def initialize(uploader, identifier, storage_key: nil)
      @uploader = uploader
      @identifier = identifier.to_s
      @storage_key = storage_key || uploader.store_path(identifier)
    end

    def path
      storage_key
    end

    def filename
      ::File.basename(identifier)
    end

    def url(*args, **options)
      positional_options = args.last.is_a?(Hash) ? args.pop : {}
      url_options = positional_options.merge(options)

      with_read_adapter { |adapter| adapter.url(storage_key, **url_options) }
    end

    def read
      with_read_adapter { |adapter| adapter.read(storage_key) }
    end

    def size
      with_read_adapter { |adapter| adapter.head(storage_key).byte_size }
    end

    def content_type
      with_read_adapter { |adapter| adapter.head(storage_key).content_type }
    end

    def exists?
      candidate_storages.any? do |storage|
        ArchiveStorage.adapter(storage).exists?(storage_key)
      rescue *fallback_errors
        false
      end
    end

    def delete
      adapter_for(current_storage).delete(storage_key)
    end

    def current_storage
      ArchiveStorage.registry.current_storage_for(
        uploader,
        identifier: identifier,
        storage_key: storage_key,
        default: policy.primary_storage_key
      )
    end

    def candidate_storages
      ([current_storage] + policy.read_fallbacks + [policy.primary_storage_key]).compact.uniq
    end

    private

    def with_read_adapter
      last_error = nil

      candidate_storages.each do |storage|
        return yield adapter_for(storage)
      rescue *fallback_errors => error
        last_error = error
      end

      raise(last_error || NotFoundError, "object #{storage_key.inspect} not found")
    end

    def adapter_for(storage)
      ArchiveStorage.adapter(storage)
    end

    def policy
      ArchiveStorage.policy_for_uploader(uploader) ||
        raise(ConfigurationError, "archive_storage policy is not configured for #{uploader.class.name}")
    end

    def fallback_errors
      ArchiveStorage.configuration.fallback_on_read_errors
    end
  end
end
