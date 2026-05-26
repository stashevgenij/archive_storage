# frozen_string_literal: true

require_relative "errors"
require_relative "adapters/metadata"
require_relative "verification_result"

module ArchiveStorage
  class Verifier
    def initialize(strategy: ArchiveStorage.configuration.verification_strategy)
      @strategy = strategy.to_sym
    end

    def verify!(source_adapter:, target_adapter:, source_key:, target_key:)
      source_metadata = source_adapter.head(source_key)
      target_metadata = target_adapter.head(target_key)

      verify_metadata!(source_metadata, target_metadata)
      verify_bytes!(source_adapter, target_adapter, source_key, target_key) if strategy == :byte_compare

      VerificationResult.new(
        strategy: strategy,
        matched_by: matched_by(source_metadata, target_metadata),
        source_metadata: source_metadata,
        target_metadata: target_metadata
      )
    end

    private

    attr_reader :strategy

    def verify_metadata!(source_metadata, target_metadata)
      verify_size!(source_metadata, target_metadata)

      case strategy
      when :auto
        verify_auto!(source_metadata, target_metadata)
      when :size
        true
      when :etag
        verify_etag!(source_metadata, target_metadata, allow_multipart: true)
      when :safe_etag
        verify_safe_etag!(source_metadata, target_metadata)
      when :checksum
        verify_checksum!(source_metadata, target_metadata)
      when :byte_compare
        true
      else
        raise ConfigurationError, "unknown verification strategy #{strategy.inspect}"
      end
    end

    def verify_size!(source_metadata, target_metadata)
      return if source_metadata.byte_size == target_metadata.byte_size

      raise VerificationError,
            "byte size mismatch: #{source_metadata.byte_size} != #{target_metadata.byte_size}"
    end

    def verify_auto!(source_metadata, target_metadata)
      if comparable_checksums?(source_metadata, target_metadata)
        verify_checksum!(source_metadata, target_metadata)
      elsif comparable_safe_etags?(source_metadata, target_metadata)
        verify_safe_etag!(source_metadata, target_metadata)
      else
        true
      end
    end

    def verify_checksum!(source_metadata, target_metadata)
      unless comparable_checksums?(source_metadata, target_metadata)
        raise VerificationError, "checksums are not available or use different algorithms"
      end

      return if source_metadata.checksum == target_metadata.checksum

      raise VerificationError,
            "checksum mismatch: #{source_metadata.checksum.inspect} != #{target_metadata.checksum.inspect}"
    end

    def verify_safe_etag!(source_metadata, target_metadata)
      unless comparable_safe_etags?(source_metadata, target_metadata)
        raise VerificationError, "safe etags are not available"
      end

      verify_etag!(source_metadata, target_metadata, allow_multipart: false)
    end

    def verify_etag!(source_metadata, target_metadata, allow_multipart:)
      unless source_metadata.etag && target_metadata.etag
        raise VerificationError, "etags are not available"
      end

      if !allow_multipart && (source_metadata.multipart_etag? || target_metadata.multipart_etag?)
        raise VerificationError, "multipart etags are not stable content checksums"
      end

      return if source_metadata.etag == target_metadata.etag

      raise VerificationError,
            "etag mismatch: #{source_metadata.etag.inspect} != #{target_metadata.etag.inspect}"
    end

    def verify_bytes!(source_adapter, target_adapter, source_key, target_key)
      source_body = source_adapter.read(source_key)
      target_body = target_adapter.read(target_key)
      return if source_body == target_body

      raise VerificationError, "byte comparison mismatch"
    end

    def comparable_checksums?(source_metadata, target_metadata)
      source_metadata.checksum &&
        target_metadata.checksum &&
        source_metadata.checksum_algorithm &&
        source_metadata.checksum_algorithm == target_metadata.checksum_algorithm
    end

    def comparable_safe_etags?(source_metadata, target_metadata)
      source_metadata.safe_etag? &&
        target_metadata.safe_etag?
    end

    def matched_by(source_metadata, target_metadata)
      case strategy
      when :checksum
        :checksum
      when :etag
        :etag
      when :safe_etag
        :safe_etag
      when :byte_compare
        :byte_compare
      when :auto
        return :checksum if comparable_checksums?(source_metadata, target_metadata)
        return :safe_etag if comparable_safe_etags?(source_metadata, target_metadata)

        :size
      else
        :size
      end
    end
  end
end
