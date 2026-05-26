# frozen_string_literal: true

require "digest"
require_relative "../errors"
require_relative "metadata"

module ArchiveStorage
    module Adapters
      class Memory
        attr_reader :config

        def initialize(config)
          @config = config
          @objects = {}
        end

        def upload(key, file, content_type: nil)
          body = read_upload_body(file)
          write(
            key,
            body,
            content_type: content_type || detect_content_type(file)
          )
        end

        def write(key, body, content_type: nil, metadata: {})
          @objects[key] = {
            body: body.to_s.b,
            content_type: content_type,
            metadata: metadata
          }
        end

        def read(key)
          object_for(key).fetch(:body)
        end

        def download_to(key, path)
          ::File.binwrite(path, read(key))
        end

        def copy_from(source_adapter, source_key, target_key)
          source_metadata = source_adapter.head(source_key)
          write(
            target_key,
            source_adapter.read(source_key),
            content_type: source_metadata.content_type,
            metadata: source_metadata.metadata || {}
          )
        end

        def head(key)
          object = object_for(key)
          body = object.fetch(:body)

          Metadata.new(
            byte_size: body.bytesize,
            content_type: object[:content_type],
            etag: Digest::MD5.hexdigest(body),
            checksum: Digest::MD5.hexdigest(body),
            checksum_algorithm: "md5",
            metadata: object[:metadata] || {}
          )
        end

        def exists?(key)
          @objects.key?(key)
        end

        def delete(key)
          @objects.delete(key)
          true
        end

        def url(key, **_options)
          raise NotFoundError, "object #{key.inspect} not found" unless exists?(key)

          "memory://#{config.name}/#{key}"
        end

        private

        def object_for(key)
          @objects.fetch(key) do
            raise NotFoundError, "object #{key.inspect} not found"
          end
        end

        def read_upload_body(file)
          return ::File.binread(file.path) if file.respond_to?(:path) && file.path
          return file.read if file.respond_to?(:read)

          file.to_s
        end

        def detect_content_type(file)
          file.content_type if file.respond_to?(:content_type)
        end
      end
    end
end
