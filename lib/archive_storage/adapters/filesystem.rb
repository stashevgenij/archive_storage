# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "../errors"
require_relative "metadata"

module ArchiveStorage
  module Adapters
    class FileSystem
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def upload(key, file, content_type: nil)
        write(key, read_upload_body(file), content_type: content_type || detect_content_type(file))
      end

      def write(key, body, content_type: nil, metadata: {})
        path = path_for(key)
        ::FileUtils.mkdir_p(::File.dirname(path))
        ::File.binwrite(path, body.to_s.b)
        write_metadata(key, content_type: content_type, metadata: metadata)
        true
      end

      def read(key)
        raise_not_found(key) unless exists?(key)

        ::File.binread(path_for(key))
      end

      def download_to(key, path)
        raise_not_found(key) unless exists?(key)

        ::FileUtils.mkdir_p(::File.dirname(path))
        ::FileUtils.cp(path_for(key), path)
      end

      def copy_from(source_adapter, source_key, target_key)
        metadata = source_adapter.head(source_key)
        write(target_key, source_adapter.read(source_key), content_type: metadata.content_type, metadata: metadata.metadata || {})
      end

      def head(key)
        raise_not_found(key) unless exists?(key)

        body = ::File.binread(path_for(key))
        stored_metadata = read_metadata(key)

        checksum = Digest::MD5.hexdigest(body)

        Metadata.new(
          byte_size: body.bytesize,
          content_type: stored_metadata[:content_type],
          etag: nil,
          checksum: checksum,
          checksum_algorithm: "md5",
          metadata: stored_metadata[:metadata] || {}
        )
      end

      def exists?(key)
        ::File.file?(path_for(key))
      end

      def delete(key)
        ::FileUtils.rm_f(path_for(key))
        ::FileUtils.rm_f(metadata_path_for(key))
        true
      end

      def url(key, **_options)
        raise_not_found(key) unless exists?(key)

        if config.base_url
          "#{config.base_url.to_s.delete_suffix("/")}/#{key}"
        else
          path_for(key)
        end
      end

      private

      def path_for(key)
        root = config.root_path || raise(ConfigurationError, "filesystem storage #{config.name.inspect} requires root_path")
        expanded_root = ::File.expand_path(root)
        expanded_path = ::File.expand_path(::File.join(expanded_root, key.to_s))

        unless expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{::File::SEPARATOR}")
          raise ConfigurationError, "storage key escapes filesystem root: #{key.inspect}"
        end

        expanded_path
      end

      def metadata_path_for(key)
        "#{path_for(key)}.archive_storage.json"
      end

      def read_upload_body(file)
        return ::File.binread(file.path) if file.respond_to?(:path) && file.path
        return file.read if file.respond_to?(:read)

        file.to_s
      end

      def detect_content_type(file)
        file.content_type if file.respond_to?(:content_type)
      end

      def write_metadata(key, content_type:, metadata:)
        return if content_type.nil? && metadata.empty?

        require "json"
        ::File.binwrite(metadata_path_for(key), JSON.dump(content_type: content_type, metadata: metadata))
      end

      def read_metadata(key)
        return {} unless ::File.file?(metadata_path_for(key))

        require "json"
        JSON.parse(::File.binread(metadata_path_for(key)), symbolize_names: true)
      rescue JSON::ParserError
        {}
      end

      def raise_not_found(key)
        raise NotFoundError, "object #{key.inspect} not found"
      end
    end
  end
end
