# archive_storage

Archival storage for Rails uploaders.

`archive_storage` moves older uploaded files from a primary storage backend to one or more archive backends, records the current file location in a registry table, and keeps reads routed through the uploader.

The gem currently supports CarrierWave. The storage, registry, and migration layers are intentionally not tied to CarrierWave, so support for other Rails uploader libraries can be added later.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [CarrierWave](#carrierwave)
- [Policies](#policies)
- [Scheduled Jobs](#scheduled-jobs)
- [Command Line](#command-line)
- [Migration Flow](#migration-flow)
- [Verification](#verification)
- [Cleanup](#cleanup)
- [Registry](#registry)
- [Development](#development)

## Features

- Model-level archive policy with `archive_storage_for :file`
- CarrierWave integration without changing shared base uploaders globally
- Multiple archive storages, for example `archive_001`, then `archive_002`
- S3-compatible storage, filesystem/NFS storage, and a memory adapter for tests
- ActiveRecord registry table for file location and migration state
- Dry-run planning
- Scheduled enqueueing
- Background migration jobs
- Copy, verify, read switch, fallback read, and delayed source cleanup
- Optional CarrierWave version/thumb migration
- GoodJob, ActiveJob, Sidekiq, `sidekiq-cron`, and `sidekiq-scheduler` support

## Installation

Add the gem to your Rails application:

```ruby
gem "archive_storage"
```

For S3-compatible storage, also add:

```ruby
gem "aws-sdk-s3"
```

Install the registry table:

```bash
bin/rails generate archive_storage:install
bin/rails db:migrate
```

## Getting Started

Configure storages:

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
end
```

Add a policy to the model that owns the upload:

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
  end
end
```

Keep the uploader focused on paths and filenames:

```ruby
class DocumentUploader < CarrierWave::Uploader::Base
  def store_dir
    "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end
end
```

Run a dry plan:

```bash
bin/rails archive_storage:plan MODEL=ProjectDocument MOUNT=file
```

Enqueue migrations:

```bash
bin/rails archive_storage:enqueue MODEL=ProjectDocument MOUNT=file LIMIT=10000
```

## Configuration

`archive_storage` needs storage definitions and, optionally, schedules and runtime defaults.

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

  config.schedule :archive_documents,
                  cron: "0 0-6,22,23 * * 1-5",
                  model: "ProjectDocument",
                  mounted_as: :file,
                  migration_rate: 10_000

  # Defaults:
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

Filesystem or NFS storage can be used as either source or archive storage:

```ruby
ArchiveStorage.configure do |config|
  config.storage :nfs_main do |s|
    s.provider = :filesystem
    s.root_path = "/mnt/uploads"
  end
end
```

## CarrierWave

`archive_storage_for` automatically wires the mounted CarrierWave uploader to `storage :archive_storage`.

```ruby
class ProjectDocument < ApplicationRecord
  mount_uploader :file, DocumentUploader

  archive_storage_for :file do
    primary :main
    archive :archive_001, after: 90.days, scope: :ready_for_archive
  end
end
```

The gem creates a per-model/per-mount uploader subclass under the model and uses that subclass internally. This avoids changing a shared uploader class globally when the same uploader is mounted by many models.

CarrierWave versions are not migrated by default. Enable them only when the generated files should follow the same archive policy:

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

## Policies

Policies are declared on the model:

```ruby
archive_storage_for :file do
  primary :main

  archive :archive_001,
          after: 90.days,
          scope: :ready_for_archive,
          max_byte_size: 3.gigabytes,
          if: ->(record) { record.closed? }

  read_fallbacks :main, :archive_001

  # delete_source_after verification: true, delay: 7.days
  # include_versions true
  # versions :thumb, :preview
  # timestamp_attribute :created_at
end
```

Policy options:

- `primary` sets the storage used for new uploads.
- `archive` adds an archive destination rule.
- `after` is checked in Ruby after records are loaded.
- `scope` narrows the ActiveRecord relation before scanning records.
- `if` applies a per-record Ruby predicate.
- `max_byte_size` skips oversized files using storage metadata and checks again before copy.
- `read_fallbacks` sets the read recovery order.
- `delete_source_after` configures the per-mount cleanup delay.
- `include_versions` and `versions` control CarrierWave versions.
- `timestamp_attribute` changes the attribute used by `after`.

For large tables, keep heavy filters in SQL:

```ruby
class ProjectDocument < ApplicationRecord
  scope :ready_for_archive, -> {
    where("created_at <= ?", 90.days.ago).where(status: "closed")
  }

  archive_storage_for :file do
    primary :main
    archive :archive_001, after: 90.days, scope: :ready_for_archive
  end
end
```

`after` is useful as a safety check, but it should not replace a selective SQL scope on large production tables.

Archive rules are checked in order. The last eligible rule wins, which allows progressive archives:

```ruby
archive_storage_for :file do
  primary :main
  archive :archive_001, after: 90.days, scope: :ready_for_archive
  archive :archive_002, after: 2.years, scope: :ready_for_archive
end
```

## Scheduled Jobs

Schedules are declared in `ArchiveStorage.configure`:

```ruby
ArchiveStorage.configure do |config|
  config.schedule :archive_documents,
                  cron: "*/10 * * * *",
                  model: "ProjectDocument",
                  mounted_as: :file,
                  migration_rate: 10_000
end
```

`migration_rate` is the maximum number of files enqueued by one scheduled run. If the cron runs every 10 minutes, `migration_rate: 10_000` means up to 10,000 files per run, not per hour.

`archive_storage` registers scheduler entries automatically. You do not need to merge `ArchiveStorage.good_job_cron` or `ArchiveStorage.sidekiq_cron` into your application config.

### GoodJob

When `good_job` is present, `archive_storage` appends its entries to `config.good_job.cron` after Rails initialization. Existing GoodJob cron entries are preserved.

Enable GoodJob cron in the environment where scheduling should run:

```ruby
# config/environments/production.rb

Rails.application.configure do
  config.good_job.enable_cron = true
end
```

### Sidekiq

Use Sidekiq workers for archive jobs:

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

On Sidekiq server startup, `archive_storage` adds its schedules without deleting existing schedules:

- with `sidekiq-cron`, it uses `Sidekiq::Cron::Job.load_from_hash`
- with `sidekiq-scheduler`, it uses `Sidekiq.set_schedule` and reloads the scheduler

Existing jobs from `sidekiq.yml`, `config/schedule.yml`, and custom initializers remain in place.

## Command Line

```bash
bin/rails archive_storage:plan MODEL=ProjectDocument MOUNT=file
bin/rails archive_storage:enqueue MODEL=ProjectDocument MOUNT=file
bin/rails archive_storage:migrate MODEL=ProjectDocument MOUNT=file
bin/rails archive_storage:verify
bin/rails archive_storage:cleanup_source
bin/rails archive_storage:status
```

Supported environment options:

```bash
MODEL=ProjectDocument
MOUNT=file
UPLOADER=DocumentUploader
OLDER_THAN=90d
LIMIT=10000
INLINE=true
ESTIMATE_SIZES=false
```

Command behavior:

- `plan` prints a dry-run plan.
- `enqueue` enqueues migration jobs.
- `migrate` enqueues migration jobs by default.
- `migrate INLINE=true` runs migration inline.
- `verify` rechecks already migrated files.
- `cleanup_source` deletes verified source copies after the cleanup delay.
- `status` prints registry counters.

`MODEL` and `MOUNT` are recommended for model-level policies. `UPLOADER` is still accepted for advanced or legacy uploader-level configurations.

## Migration Flow

The migration process is intentionally staged:

```text
source only
source + archive copied
archive verified
registry points reads to archive
reads can fallback to source
source deleted later when cleanup is enabled
```

This keeps the application reading through the uploader while files are being copied and verified.

## Verification

The default verification strategy is `:auto`.

`archive_storage` does not blindly trust S3 ETags. Multipart S3 uploads can have ETags like `hash-3`, and uploading the same bytes to another storage can produce a different ETag.

Available strategies:

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

For filesystem/NFS sources, checksums are based on the bytes read from disk. For S3-compatible sources, checksum and ETag metadata are used when available according to the configured strategy.

## Cleanup

Source deletion is disabled by default:

```ruby
ArchiveStorage.configure do |config|
  config.delete_source_enabled = false
end
```

Enable it only after planning, migration, and reads have been verified in production:

```ruby
ArchiveStorage.configure do |config|
  config.delete_source_enabled = true
end
```

It can also be a callable, which is useful for feature flags:

```ruby
ArchiveStorage.configure do |config|
  config.delete_source_enabled = -> { Unleash.enabled?(:archive_storage_delete_source) }
end
```

Configure cleanup delay per mount:

```ruby
archive_storage_for :file do
  primary :main
  archive :archive_001, after: 90.days, scope: :ready_for_archive
  delete_source_after verification: true, delay: 7.days
end
```

Run cleanup:

```bash
bin/rails archive_storage:cleanup_source
```

## Registry

The generated migration creates `archive_storage_files`.

The registry stores:

- model identity: `record_type`, `record_id`, `mounted_as`, `uploader`
- object identity: `identifier`, `storage_key`, `source_storage_key`, `target_storage_key`
- storage state: `current_storage`, `source_storage`, `target_storage`
- migration state: `enqueued_at`, `migration_started_at`, `migrated_at`, `verified_at`, `source_deleted_at`
- metadata: `byte_size`, `checksum`, `content_type`, `attempts`, `last_error`

The registry has a unique identity index on:

```text
record_type, record_id, mounted_as, identifier, storage_key
```

Business tables do not need extra columns for archive location.

If an application generated an older migration without the unique identity index, add a migration that replaces the old identity index with the unique one before relying on parallel enqueueing.

## Development

Run the test suite:

```bash
bundle exec rake test
```

Build the gem:

```bash
bundle exec gem build archive_storage.gemspec
```

## License

MIT.
