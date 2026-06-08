# archive_storage

Zero-downtime archival storage for CarrierWave uploads.

`archive_storage` moves older uploaded files from one storage backend to another, keeps a registry of the current file location, and routes reads to the right backend. It currently integrates with CarrierWave; support for other uploader libraries can be added later without changing the registry model.

Supported storage adapters:

- S3-compatible object storage, including MinIO and AWS S3
- filesystem/NFS
- memory adapter for tests

Typical use cases:

- `main` S3/MinIO bucket -> `archive_001` cold bucket
- `archive_001` -> `archive_002` when the first archive fills up
- NFS/local disk -> S3-compatible archive storage

## Features

- model-first DSL: `archive_storage_for :file`
- automatic CarrierWave storage wiring
- ActiveRecord registry table: `archive_storage_files`
- dry-run planning
- scheduled enqueueing
- background migration jobs
- copy, verify, read switch, fallback read, delayed source cleanup
- optional CarrierWave versions/thumbs migration
- GoodJob, ActiveJob, Sidekiq, `sidekiq-cron`, and `sidekiq-scheduler` support

## Installation

Add the gem:

```ruby
gem "archive_storage"
```

For S3-compatible storage:

```ruby
gem "aws-sdk-s3"
```

Install the registry table:

```bash
bin/rails generate archive_storage:install
bin/rails db:migrate
```

## Configuration

Define the storage backends and scheduled archive jobs.

```ruby
# config/initializers/archive_storage.rb

ArchiveStorage.configure do |config|
  config.storage :main do |s|
    s.provider = :s3
    s.endpoint = ENV.fetch("MAIN_STORAGE_ENDPOINT")
    s.bucket = "production-main"
    s.access_key_id = ENV.fetch("MAIN_STORAGE_ACCESS_KEY")
    s.secret_access_key = ENV.fetch("MAIN_STORAGE_SECRET_KEY")
    s.region = "us-east-1"
    s.path_style = true
  end

  config.storage :archive_001 do |s|
    s.provider = :s3
    s.endpoint = ENV.fetch("ARCHIVE_001_ENDPOINT")
    s.bucket = "production-archive-001"
    s.access_key_id = ENV.fetch("ARCHIVE_001_ACCESS_KEY")
    s.secret_access_key = ENV.fetch("ARCHIVE_001_SECRET_KEY")
    s.region = "us-east-1"
    s.path_style = true
  end

  config.storage :archive_002 do |s|
    s.provider = :s3
    s.endpoint = ENV.fetch("ARCHIVE_002_ENDPOINT")
    s.bucket = "production-archive-002"
    s.access_key_id = ENV.fetch("ARCHIVE_002_ACCESS_KEY")
    s.secret_access_key = ENV.fetch("ARCHIVE_002_SECRET_KEY")
    s.region = "us-east-1"
    s.path_style = true
  end

  config.schedule :archive_documents,
                  cron: "0 0-6,22,23 * * 1-5",
                  model: "ProjectDocument",
                  mounted_as: :file,
                  migration_rate: 10_000

  # Optional defaults:
  #
  # config.job_backend = :active_job # :active_job, :good_job, :sidekiq, or :inline
  # config.migration_queue = :default
  # config.schedule_queue = :default
  # config.default_batch_size = 500
  # config.verification_strategy = :auto
  # config.delete_source_enabled = false
  # config.default_cleanup_delay = 7.days
end
```

Filesystem/NFS storage can be mixed with S3-compatible storage:

```ruby
config.storage :nfs_main do |s|
  s.provider = :filesystem
  s.root_path = "/mnt/uploads"
end
```

## Model Policy

Put archive policy next to the model that owns the file.

```ruby
class ProjectDocument < ApplicationRecord
  scope :ready_for_archive, -> { where("created_at <= ?", 90.days.ago) }

  mount_uploader :file, DocumentUploader

  archive_storage_for :file do
    primary :main

    archive :archive_001,
      after: 90.days,
      scope: :ready_for_archive,
      max_byte_size: 3.gigabytes,
      if: ->(record) { record.closed? }

    archive :archive_002,
      after: 2.years,
      scope: ->(records) { records.where(priority: "low") },
      if: ->(record) { record.closed? }

    read_fallbacks :main, :archive_001, :archive_002

    # Optional:
    #
    # delete_source_after verification: true, delay: 7.days
    # include_versions true
    # versions :thumb, :preview
    # timestamp_attribute :created_at
  end
end
```

`archive_storage_for` automatically wires the mounted CarrierWave uploader to `storage :archive_storage`.

To avoid changing shared base uploaders globally, the gem creates a per-model/per-mount uploader subclass under the model and mounts that subclass internally. The original uploader can stay focused on path, filename, and version behavior:

```ruby
class DocumentUploader < CarrierWave::Uploader::Base
  def store_dir
    "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end
end
```

Policy notes:

- `primary` is where new uploads are stored.
- `archive` rules are checked in order; the last eligible rule wins.
- `scope` narrows the model relation before records are scanned. It can be a model scope name, a relation, or a callable that receives the current relation.
- `after` is checked in Ruby after records are loaded. Keep heavy date filters, such as `created_at <= 2.months.ago`, inside the SQL `scope`.
- `max_byte_size` skips oversized files using storage metadata before enqueueing and is checked again before migration.
- `read_fallbacks` is the read-recovery order when registry metadata is missing or a configured fallback error is raised.
- By default only the original CarrierWave file is planned. Use `include_versions true` or `versions ...` when thumbnails/previews must move too.

## Scheduled Jobs

Schedules are declared in global configuration:

```ruby
ArchiveStorage.configure do |config|
  config.schedule :archive_documents,
                  cron: "0 0-6,22,23 * * 1-5",
                  model: "ProjectDocument",
                  mounted_as: :file,
                  migration_rate: 10_000
end
```

`migration_rate` means at most this many files are enqueued by one scheduled run.

`archive_storage` registers scheduler entries automatically. You do not need to merge `ArchiveStorage.good_job_cron` or `ArchiveStorage.sidekiq_cron` into your application config.

### GoodJob

When `good_job` is present, `archive_storage` appends its entries to `config.good_job.cron` after Rails initialization. Existing GoodJob cron entries are preserved.

Enable GoodJob cron in the app environment where the scheduler should run:

```ruby
# config/environments/production.rb

Rails.application.configure do
  config.good_job.enable_cron = true
end
```

### Sidekiq

Use Sidekiq for migration jobs:

```ruby
# config/initializers/archive_storage.rb

ArchiveStorage.configure do |config|
  config.job_backend = :sidekiq
end
```

Add one scheduler gem:

```ruby
gem "sidekiq-cron"
# or
gem "sidekiq-scheduler"
```

On Sidekiq server startup, `archive_storage` adds its own schedules without deleting existing jobs:

- with `sidekiq-cron`, it uses non-destructive `Sidekiq::Cron::Job.load_from_hash`
- with `sidekiq-scheduler`, it uses `Sidekiq.set_schedule` and reloads the scheduler

Existing jobs from `sidekiq.yml`, `config/schedule.yml`, or custom initializers remain in place.

## Commands

```bash
bin/rails archive_storage:plan MODEL=ProjectDocument MOUNT=file
bin/rails archive_storage:enqueue MODEL=ProjectDocument MOUNT=file
bin/rails archive_storage:migrate MODEL=ProjectDocument MOUNT=file
bin/rails archive_storage:verify
bin/rails archive_storage:cleanup_source
bin/rails archive_storage:status
```

Options:

```bash
MODEL=ProjectDocument
MOUNT=file
OLDER_THAN=90d
LIMIT=10000
INLINE=true
ESTIMATE_SIZES=false
```

`UPLOADER=DocumentUploader` is still accepted for advanced/legacy uploader-level configurations.

Command behavior:

- `plan` prints a dry-run plan.
- `enqueue` and `migrate` enqueue migration jobs by default.
- `migrate INLINE=true` runs migration inline.
- `verify` re-checks already migrated files.
- `cleanup_source` deletes verified source copies that are past the cleanup delay.
- `status` prints registry counters.

## Migration Flow

```text
source only
source + destination copied
destination verified
registry points reads to destination
reads can fallback to source
source deleted later when cleanup is enabled
```

Source deletion is disabled by default:

```ruby
config.delete_source_enabled = false
```

Turn it on only after the migration path has been verified in production:

```ruby
config.delete_source_enabled = true
```

It can also be a callable, which is useful for feature flags:

```ruby
config.delete_source_enabled = -> { Unleash.enabled?(:archive_storage_delete_source) }
```

Per-mount cleanup delay:

```ruby
archive_storage_for :file do
  delete_source_after verification: true, delay: 7.days
end
```

## Verification

The default strategy is `:auto`.

`archive_storage` does not blindly trust S3 ETags. Multipart S3 uploads can have ETags like `hash-3`, and uploading the same bytes to another storage can produce a different ETag.

Strategies:

- `:auto` - size check, then checksum when available, then non-multipart ETag, otherwise size-only
- `:checksum` - require matching checksums
- `:safe_etag` - require matching non-multipart ETags
- `:etag` - require matching ETags, including multipart-looking values
- `:byte_compare` - compare full file bytes after size check
- `:size` - compare content length only

```ruby
ArchiveStorage.configure do |config|
  config.verification_strategy = :auto
end
```

## Registry

The generated migration creates `archive_storage_files`.

The registry has a unique identity index on:

```text
record_type, record_id, mounted_as, identifier, storage_key
```

The registry stores:

- model identity: `record_type`, `record_id`, `mounted_as`, `uploader`
- object identity: `identifier`, `storage_key`, source/target keys
- storage state: `current_storage`, `source_storage`, `target_storage`
- migration state: enqueue, migration, verification, cleanup timestamps
- metadata: byte size, checksum, content type, attempts, last error

Business tables do not need extra columns for archive location.

## CarrierWave Versions

CarrierWave versions are disabled by default.

```ruby
archive_storage_for :file do
  include_versions true
end
```

To migrate only selected versions:

```ruby
archive_storage_for :file do
  versions :thumb, :preview
end
```

Use this only when those files are stored and read as part of the same archival policy. It can multiply the number of objects planned for migration.

## Current Scope

This MVP is focused on Rails, ActiveRecord, and CarrierWave. The storage and registry layers are not CarrierWave-specific, so other uploader integrations can be added later.
