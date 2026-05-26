# frozen_string_literal: true

require_relative "../test_helper"

class StorageTest < Minitest::Test
  include ArchiveStorageTestConfig

  def setup
    reset_archive_storage!
  end

  def test_stores_new_uploads_in_hot_storage
    uploader = FakeUploader.new
    storage = ArchiveStorage::Storage.new(uploader)

    file = storage.store!(TestUpload.new("report.txt", "hello"))

    assert_equal "hello", file.read
    assert_equal "memory://hot/uploads/1/report.txt", file.url
  end

  def test_reads_from_fallback_when_current_storage_is_missing
    uploader = FakeUploader.new
    archive = ArchiveStorage.adapter(:archive)
    archive.write("uploads/1/report.txt", "archived", content_type: "text/plain")

    file = ArchiveStorage::StoredFile.new(uploader, "report.txt")

    assert_equal "archived", file.read
    assert_equal "memory://archive/uploads/1/report.txt", file.url
  end

  def test_integrates_with_carrierwave_store_api
    tempfile = Tempfile.new(["report", ".txt"])
    tempfile.write("hello")
    tempfile.rewind

    uploader = CarrierWaveSmokeUploader.new
    uploader.store!(tempfile)

    assert_match %r{\Amemory://hot/uploads/smoke/report}, uploader.url
    assert_equal "hello", uploader.file.read
  ensure
    tempfile&.close!
  end

  def test_model_first_macro_wires_carrierwave_storage
    ModelFirstRecord.configure_archive_storage!
    uploader = ModelFirstRecord.new(id: 9).file
    tempfile = Tempfile.new(["report", ".txt"])
    tempfile.write("hello from model")
    tempfile.rewind

    uploader.store!(tempfile)

    assert_equal "hello from model", uploader.file.read
    assert_match %r{\Amemory://hot/uploads/model_first/9/report}, uploader.url
  ensure
    tempfile&.close!
  end

  def test_filesystem_adapter_can_act_as_an_archive_storage_member
    Dir.mktmpdir("archive-storage") do |root|
      ArchiveStorage.configure do |config|
        config.storage(:nfs_archive) do |storage|
          storage.provider = :filesystem
          storage.root_path = root
        end
      end

      adapter = ArchiveStorage.adapter(:nfs_archive)
      adapter.write("uploads/report.txt", "from disk", content_type: "text/plain")

      assert_equal "from disk", adapter.read("uploads/report.txt")
      assert_equal 9, adapter.head("uploads/report.txt").byte_size
      assert adapter.url("uploads/report.txt").start_with?(root)
    end
  end
end
