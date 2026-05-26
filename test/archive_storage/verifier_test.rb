# frozen_string_literal: true

require_relative "../test_helper"

class VerifierTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
  end

  def test_auto_verification_falls_back_to_size_when_s3_source_has_multipart_etag
    source = ArchiveStorage::Adapters::Metadata.new(
      byte_size: 5,
      content_type: "text/plain",
      etag: "abc-1"
    )
    target = ArchiveStorage::Adapters::Metadata.new(
      byte_size: 5,
      content_type: "text/plain",
      etag: "def"
    )

    result = verifier_result(source, target)

    assert_equal :size, result.matched_by
  end

  def test_auto_verification_uses_filesystem_checksums_when_available
    source = ArchiveStorage::Adapters::Metadata.new(
      byte_size: 5,
      checksum: "abc",
      checksum_algorithm: "md5"
    )
    target = ArchiveStorage::Adapters::Metadata.new(
      byte_size: 5,
      checksum: "abc",
      checksum_algorithm: "md5"
    )

    result = verifier_result(source, target)

    assert_equal :checksum, result.matched_by
  end

  def test_checksum_strategy_rejects_checksum_mismatch
    source = ArchiveStorage::Adapters::Metadata.new(
      byte_size: 5,
      checksum: "abc",
      checksum_algorithm: "md5"
    )
    target = ArchiveStorage::Adapters::Metadata.new(
      byte_size: 5,
      checksum: "def",
      checksum_algorithm: "md5"
    )

    assert_raises(ArchiveStorage::VerificationError) do
      verifier_result(source, target, strategy: :checksum)
    end
  end

  private

  def verifier_result(source_metadata, target_metadata, strategy: :auto)
    source = FakeAdapter.new(source_metadata)
    target = FakeAdapter.new(target_metadata)

    ArchiveStorage::Verifier.new(strategy: strategy).verify!(
      source_adapter: source,
      target_adapter: target,
      source_key: "source",
      target_key: "target"
    )
  end

  class FakeAdapter
    def initialize(metadata)
      @metadata = metadata
    end

    def head(_key)
      @metadata
    end

    def read(_key)
      "hello"
    end
  end
end
