# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "stringio"
require "tempfile"
require "tmpdir"
require "archive_storage"

class TestUpload
  attr_reader :filename, :content_type

  def initialize(filename, body, content_type: "text/plain")
    @filename = filename
    @body = body
    @content_type = content_type
  end

  def read
    @body
  end
end

class FakeModel
  attr_reader :id, :created_at

  def initialize(id: 1, created_at: Time.now)
    @id = id
    @created_at = created_at
  end

  def closed?
    true
  end
end

class FakeUploader
  include ArchiveStorage::CarrierWave

  attr_reader :model, :mounted_as

  archive_storage do
    hot :hot
    archive :archive, after: 90 * 24 * 60 * 60, if: ->(record) { record.closed? }
    read_fallbacks :hot, :archive
    delete_source_after verification: true, delay: 7 * 24 * 60 * 60
  end

  def initialize(model = FakeModel.new)
    @model = model
    @mounted_as = :file
  end

  def store_path(identifier)
    "uploads/#{model.id}/#{identifier}"
  end
end

class CarrierWaveSmokeUploader < CarrierWave::Uploader::Base
  include ArchiveStorage::CarrierWave

  storage :archive_storage

  archive_storage do
    hot :hot
    archive :archive, after: 1
    read_fallbacks :hot, :archive
  end

  def store_dir
    "uploads/smoke"
  end
end

class ScheduledDocumentUploader < CarrierWave::Uploader::Base
  include ArchiveStorage::CarrierWave

  storage :archive_storage

  archive_storage do
    primary :hot
    archive :archive, after: 90 * 24 * 60 * 60
  end

  def store_dir
    "uploads/scheduled"
  end
end

class VersionedRecordScope
  def initialize(records)
    @records = records
  end

  def find_each(batch_size: nil)
    @records.each { |record| yield record }
  end
end

class VersionedRecord
  attr_reader :id, :created_at

  def self.records
    @records ||= []
  end

  def self.all
    VersionedRecordScope.new(records)
  end

  def self.column_names
    []
  end

  def initialize(id: 1, created_at: Time.now - 120 * 24 * 60 * 60)
    @id = id
    @created_at = created_at
  end

  def closed?
    true
  end

  def file
    @file ||= VersionedUploader.new(self, :file).tap do |uploader|
      uploader.retrieve_from_store!("report.txt")
    end
  end
end

class VersionedUploader < CarrierWave::Uploader::Base
  include ArchiveStorage::CarrierWave

  storage :archive_storage

  version :thumb

  archive_storage do
    hot :hot
    archive :archive, after: 90 * 24 * 60 * 60
    read_fallbacks :hot, :archive
    include_versions true
  end

  def store_dir
    "uploads/versioned"
  end
end

class ScopedRecordScope
  def initialize(records)
    @records = records
  end

  def for_archive
    self.class.new(@records.select(&:archivable?))
  end

  def find_each(batch_size: nil)
    @records.each { |record| yield record }
  end
end

class ScopedRecord
  attr_reader :id, :created_at

  def self.records
    @records ||= []
  end

  def self.all
    ScopedRecordScope.new(records)
  end

  def self.column_names
    []
  end

  def initialize(id:, archivable:)
    @id = id
    @archivable = archivable
    @created_at = Time.now - 120 * 24 * 60 * 60
  end

  def archivable?
    @archivable
  end

  def file
    @file ||= ScopedUploader.new(self, :file).tap do |uploader|
      uploader.retrieve_from_store!("report-#{id}.txt")
    end
  end
end

class ScopedUploader < CarrierWave::Uploader::Base
  include ArchiveStorage::CarrierWave

  storage :archive_storage

  archive_storage do
    primary :hot
    archive :archive, after: 90 * 24 * 60 * 60, scope: :for_archive
  end

  def store_dir
    "uploads/scoped/#{model.id}"
  end
end

class ModelFirstUploader < CarrierWave::Uploader::Base
  def store_dir
    "uploads/model_first/#{model.id}"
  end
end

class ModelFirstRecordScope
  def initialize(records)
    @records = records
  end

  def ready_for_archive
    self.class.new(@records.select(&:ready_for_archive?))
  end

  def find_each(batch_size: nil)
    @records.each { |record| yield record }
  end
end

class ModelFirstRecord
  extend ArchiveStorage::Model

  attr_reader :id, :created_at

  def self.records
    @records ||= []
  end

  def self.all
    ModelFirstRecordScope.new(records)
  end

  def self.column_names
    []
  end

  def self.uploaders
    @uploaders ||= { file: ModelFirstUploader }
  end

  def self.configure_archive_storage!
    archive_storage_for :file do
      primary :hot
      archive :archive, after: 90 * 24 * 60 * 60, scope: :ready_for_archive
      read_fallbacks :hot, :archive
    end
  end

  def self.configure_archive_storage_with_max!(max_byte_size)
    archive_storage_for :file do
      primary :hot
      archive :archive,
              after: 90 * 24 * 60 * 60,
              scope: :ready_for_archive,
              max_byte_size: max_byte_size
      read_fallbacks :hot, :archive
    end
  end

  def self.configure_archive_storage_to_second_archive_with_max!(max_byte_size)
    archive_storage_for :file do
      primary :hot
      archive :archive,
              after: 90 * 24 * 60 * 60,
              scope: :ready_for_archive
      archive :archive_002,
              after: 90 * 24 * 60 * 60,
              scope: :ready_for_archive,
              max_byte_size: max_byte_size
      read_fallbacks :hot, :archive, :archive_002
    end
  end

  def initialize(id: 1, ready: true, created_at: Time.now - 120 * 24 * 60 * 60)
    @id = id
    @ready = ready
    @created_at = created_at
  end

  def ready_for_archive?
    @ready
  end

  def file
    @file ||= self.class.uploaders.fetch(:file).new(self, :file).tap do |uploader|
      uploader.retrieve_from_store!("report-#{id}.txt")
    end
  end
end

class FakeFileRecord
  ATTRS = [
    :id,
    :record_type,
    :record_id,
    :mounted_as,
    :uploader,
    :storage_key,
    :source_storage_key,
    :target_storage_key,
    :current_storage,
    :source_storage,
    :target_storage,
    :byte_size,
    :content_type,
    :checksum,
    :enqueued_at,
    :next_attempt_at,
    :migration_started_at,
    :migrated_at,
    :verified_at,
    :source_deleted_at,
    :terminal_failed_at,
    :source_delete_pending,
    :last_error,
    :attempts
  ].freeze

  attr_accessor(*ATTRS)

  def initialize(attrs = {})
    attrs.each { |key, value| public_send("#{key}=", value) }
  end

  def with_lock
    yield
  end

  def update!(attrs)
    attrs.each { |key, value| public_send("#{key}=", value) }
  end
end

class AttachmentUploader < CarrierWave::Uploader::Base
  def store_dir
    "uploads/attachments/#{model.id}"
  end
end

class GroAttachmentUploader < CarrierWave::Uploader::Base
  def store_dir
    "uploads/gro_auth_representatives/#{model.id}"
  end
end

class AttachmentRecordScope
  def initialize(records)
    @records = records
  end

  def for_archive
    self.class.new(@records.reject(&:gro_auth_representative?))
  end

  def find_each(batch_size: nil)
    @records.each { |record| yield record }
  end
end

class Attachment
  extend ArchiveStorage::Model

  attr_reader :id, :created_at

  def self.records
    @records ||= []
  end

  def self.all
    AttachmentRecordScope.new(records)
  end

  def self.column_names
    []
  end

  def self.uploaders
    @uploaders ||= { file: AttachmentUploader }
  end

  def self.configure_archive_storage!
    archive_storage_for :file do
      primary :hot
      archive :archive, after: 90 * 24 * 60 * 60, scope: :for_archive
      read_fallbacks :hot, :archive
    end
  end

  def initialize(id:, gro: false, created_at: Time.now - 120 * 24 * 60 * 60)
    @id = id
    @gro = gro
    @created_at = created_at
  end

  def gro_auth_representative?
    @gro
  end

  def file
    @file ||= self.class.uploaders.fetch(:file).new(self, :file).tap do |uploader|
      uploader.retrieve_from_store!("attachment-#{id}.txt")
    end
  end
end

module Organization
  class GroAuthRepresentative
    class Attachment
      extend ArchiveStorage::Model

      attr_reader :id, :created_at

      def self.records
        @records ||= []
      end

      def self.all
        AttachmentRecordScope.new(records)
      end

      def self.column_names
        []
      end

      def self.uploaders
        @uploaders ||= { file: GroAttachmentUploader }
      end

      def self.configure_archive_storage!
        archive_storage_for :file do
          primary :hot
          archive :archive_002, after: 90 * 24 * 60 * 60
          read_fallbacks :hot, :archive_002
        end
      end

      def initialize(id:, created_at: Time.now - 120 * 24 * 60 * 60)
        @id = id
        @created_at = created_at
      end

      def gro_auth_representative?
        true
      end

      def file
        @file ||= self.class.uploaders.fetch(:file).new(self, :file).tap do |uploader|
          uploader.retrieve_from_store!("gro-attachment-#{id}.txt")
        end
      end
    end
  end
end

module ArchiveStorageTestConfig
  def reset_archive_storage!
    ArchiveStorage.reset_configuration!
    ArchiveStorage.configure do |config|
      config.storage(:hot) { |storage| storage.provider = :memory }
      config.storage(:archive) { |storage| storage.provider = :memory }
      config.verify_checksums = true
    end
  end
end
