# frozen_string_literal: true

module ArchiveStorage
  module Adapters
    Metadata = Struct.new(
      :byte_size,
      :content_type,
      :etag,
      :checksum,
      :checksum_algorithm,
      :metadata,
      keyword_init: true
    ) do
      def multipart_etag?
        etag.to_s.include?("-")
      end

      def safe_etag?
        etag && !multipart_etag?
      end
    end
  end
end
