# frozen_string_literal: true

class CreateArchiveStorageFiles < ActiveRecord::Migration[7.0]
  def change
    create_table :archive_storage_files do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :mounted_as, null: false
      t.string :uploader, null: false

      t.string :identifier, null: false
      t.string :storage_key, null: false
      t.string :source_storage_key
      t.string :target_storage_key

      t.string :current_storage, null: false
      t.string :source_storage
      t.string :target_storage

      t.bigint :byte_size
      t.string :checksum
      t.string :content_type

      t.datetime :migration_started_at
      t.datetime :enqueued_at
      t.datetime :migrated_at
      t.datetime :verified_at
      t.datetime :source_deleted_at

      t.boolean :source_delete_pending, null: false, default: false
      t.string :last_error
      t.integer :attempts, null: false, default: 0

      t.timestamps
    end

    add_index :archive_storage_files,
              [:record_type, :record_id, :mounted_as, :identifier],
              name: "idx_archive_storage_identity"

    add_index :archive_storage_files,
              [:uploader, :current_storage],
              name: "idx_archive_storage_uploader_storage"

    add_index :archive_storage_files,
              [:source_storage, :source_deleted_at],
              name: "idx_archive_storage_cleanup"

    add_index :archive_storage_files,
              [:source_delete_pending, :source_deleted_at],
              name: "idx_archive_storage_delete_pending"
  end
end
