# frozen_string_literal: true

require "cgi"
require "stringio"
require "tempfile"
require_relative "../errors"
require_relative "metadata"

module ArchiveStorage
    module Adapters
      class S3
        attr_reader :config

        def initialize(config)
          @config = config
        end

        def upload(key, file, content_type: nil)
          body, close_body = upload_body(file)

          client.put_object(
            bucket: config.bucket,
            key: key,
            body: body,
            content_type: content_type || detect_content_type(file)
          )
        ensure
          body.close if close_body && body.respond_to?(:close)
        end

        def upload_path(key, path, content_type: nil)
          ::File.open(path, "rb") do |file|
            client.put_object(
              bucket: config.bucket,
              key: key,
              body: file,
              content_type: content_type
            )
          end
        end

        def read(key)
          client.get_object(bucket: config.bucket, key: key).body.read
        rescue not_found_errors => error
          raise NotFoundError, error.message
        end

        def download_to(key, path)
          ::File.open(path, "wb") do |file|
            client.get_object(bucket: config.bucket, key: key) do |chunk|
              file.write(chunk)
            end
          end
        rescue not_found_errors => error
          raise NotFoundError, error.message
        end

        def copy_from(source_adapter, source_key, target_key)
          source_metadata = source_adapter.head(source_key)

          Tempfile.create("archive-storage-copy") do |tempfile|
            tempfile.binmode
            source_adapter.download_to(source_key, tempfile.path)
            upload_path(target_key, tempfile.path, content_type: source_metadata.content_type)
          end
        end

        def head(key)
          response = client.head_object(bucket: config.bucket, key: key)

          Metadata.new(
            byte_size: response.content_length,
            content_type: response.content_type,
            etag: clean_etag(response.etag),
            checksum: response_checksum(response),
            checksum_algorithm: response_checksum_algorithm(response),
            metadata: response.metadata || {}
          )
        rescue not_found_errors => error
          raise NotFoundError, error.message
        end

        def exists?(key)
          head(key)
          true
        rescue NotFoundError
          false
        end

        def delete(key)
          client.delete_object(bucket: config.bucket, key: key)
          true
        end

        def url(key, expires_in: 3600, public: nil, **_options)
          if public || config.public?
            public_url(key)
          else
            presigner.presigned_url(
              :get_object,
              bucket: config.bucket,
              key: key,
              expires_in: expires_in
            )
          end
        end

        def client
          @client ||= begin
            require "aws-sdk-s3"

            Aws::S3::Client.new(client_options)
          end
        end

        private

        def client_options
          {
            access_key_id: config.access_key_id,
            secret_access_key: config.secret_access_key,
            region: config.region,
            endpoint: config.endpoint,
            force_path_style: config.path_style?
          }.compact.merge(config.options || {})
        end

        def presigner
          require "aws-sdk-s3"
          Aws::S3::Presigner.new(client: client)
        end

        def public_url(key)
          host = config.public_host || "#{config.endpoint}/#{config.bucket}"
          "#{host.to_s.delete_suffix("/")}/#{escape_key(key)}"
        end

        def upload_body(file)
          if file.respond_to?(:path) && file.path
            [::File.open(file.path, "rb"), true]
          elsif file.respond_to?(:to_file) && file.to_file
            [file.to_file, false]
          elsif file.respond_to?(:read)
            [file, false]
          else
            [StringIO.new(file.to_s), true]
          end
        end

        def detect_content_type(file)
          file.content_type if file.respond_to?(:content_type)
        end

        def clean_etag(etag)
          etag&.delete_prefix("\"")&.delete_suffix("\"")
        end

        def response_checksum(response)
          checksum_algorithm = response_checksum_algorithm(response)
          return nil unless checksum_algorithm

          response.public_send("checksum_#{checksum_algorithm}") if response.respond_to?("checksum_#{checksum_algorithm}")
        end

        def response_checksum_algorithm(response)
          %w[sha256 sha1 crc32c crc32].find do |algorithm|
            response.respond_to?("checksum_#{algorithm}") &&
              response.public_send("checksum_#{algorithm}")
          end
        end

        def escape_key(key)
          key.to_s.split("/").map { |part| CGI.escape(part) }.join("/")
        end

        def not_found_errors
          require "aws-sdk-s3"
          [
            Aws::S3::Errors::NoSuchKey,
            Aws::S3::Errors::NotFound,
            Aws::S3::Errors::NoSuchBucket
          ]
        end
      end
    end
end
