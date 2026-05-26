# frozen_string_literal: true

require_relative "stored_file"

module ArchiveStorage
  class Storage
    attr_reader :uploader, :identifier

    def initialize(uploader)
      @uploader = uploader
    end

    def store!(file)
      identifier = identifier_for(file)
      @identifier = identifier
      storage_key = uploader.store_path(identifier)
      primary_storage = policy.primary_storage_key
      adapter = ArchiveStorage.adapter(primary_storage)

      adapter.upload(storage_key, file)
      metadata = safe_head(adapter, storage_key)

      ArchiveStorage.registry.upsert_for_uploader(
        uploader,
        identifier: identifier,
        storage_key: storage_key,
        current_storage: primary_storage,
        metadata: {
          byte_size: metadata&.byte_size,
          content_type: metadata&.content_type,
          checksum: metadata&.etag
        }
      )

      StoredFile.new(uploader, identifier, storage_key: storage_key)
    end

    def retrieve!(identifier)
      @identifier = identifier
      StoredFile.new(
        uploader,
        identifier,
        storage_key: uploader.store_path(identifier)
      )
    end

    def cache!(new_file)
      file_cache_storage.cache!(new_file)
    end

    def retrieve_from_cache!(identifier)
      file_cache_storage.retrieve_from_cache!(identifier)
    end

    def delete_dir!(path)
      file_cache_storage.delete_dir!(path)
    end

    def clean_cache!(seconds)
      file_cache_storage.clean_cache!(seconds)
    end

    private

    def identifier_for(file)
      return file.filename if file.respond_to?(:filename) && file.filename
      return uploader.filename if uploader.respond_to?(:filename) && uploader.filename

      raise ArgumentError, "cannot infer upload identifier for archive storage upload"
    end

    def policy
      ArchiveStorage.policy_for_uploader(uploader) ||
        raise(ConfigurationError, "archive_storage policy is not configured for #{uploader.class.name}")
    end

    def safe_head(adapter, storage_key)
      adapter.head(storage_key)
    rescue StandardError
      nil
    end

    def file_cache_storage
      unless defined?(::CarrierWave::Storage::File)
        raise ConfigurationError, "CarrierWave file storage is required for archive_storage cache storage"
      end

      @file_cache_storage ||= ::CarrierWave::Storage::File.new(uploader)
    end
  end
end
