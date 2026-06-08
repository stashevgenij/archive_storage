# frozen_string_literal: true

require_relative "duration_parser"
require_relative "plan_result"

module ArchiveStorage
  Candidate = Struct.new(
    :record,
    :mounted_as,
    :uploader,
    :identifier,
    :storage_key,
    :source_storage_key,
    :target_storage_key,
    :current_storage,
    :target_storage,
    :byte_size,
    :content_type,
    keyword_init: true
  )

  class Planner
    attr_reader :uploader_name,
                :model_name,
                :mounted_as,
                :older_than,
                :limit,
                :estimate_sizes

    def initialize(uploader: nil, model: nil, mounted_as: nil, older_than: nil, limit: nil, estimate_sizes: false)
      @uploader_name = uploader
      @model_name = model
      @mounted_as = mounted_as&.to_sym
      @older_than = DurationParser.parse(older_than)
      @limit = limit&.to_i
      @estimate_sizes = estimate_sizes
    end

    def call
      result = PlanResult.new(uploader_name: uploader_name)
      each_candidate { |candidate| result.add(candidate) }
      result
    end

    def each_candidate
      return enum_for(:each_candidate) unless block_given?

      count = 0
      mounts.each do |mount|
        each_record(mount) do |record|
          candidates_for(record, mount).each do |candidate|
            yield candidate
            count += 1
            return if limit && count >= limit
          end
        end
      end
    end

    private

    def mounts
      if model_name && mounted_as
        [ArchiveStorage.configuration.find_mount(model_name, mounted_as) ||
          MountConfig.new(model_name, mounted_as, uploader: uploader_name)]
      else
        ArchiveStorage.configuration.mounts.select do |mount|
          mount.matches_uploader?(uploader_name)
        end
      end
    end

    def each_record(mount)
      klass = mount.model_class
      scope = scoped_records_for(klass, mount)

      if klass.respond_to?(:column_names) && klass.column_names.include?(mount.mounted_as.to_s)
        scope = scope.where.not(mount.mounted_as => [nil, ""])
      end

      scope.find_each(batch_size: ArchiveStorage.configuration.default_batch_size) do |record|
        yield record
      end
    end

    def candidates_for(record, mount)
      return [] if too_young?(record)

      uploader = record.public_send(mount.mounted_as)
      identifier = identifier_for(record, uploader, mount)
      return [] if identifier.nil? || identifier == ""

      policy = policy_for(record, mount, uploader)
      return [] unless policy

      uploaders_for(uploader, policy).filter_map do |mounted_uploader|
        candidate_for_uploader(record, mount, mounted_uploader, identifier, policy)
      end
    end

    def scoped_records_for(klass, mount)
      scope = klass.all
      policy = ArchiveStorage.policy_for_mount(klass, mount.mounted_as) || uploader_policy_for(mount)

      policy ? policy.apply_rule_scopes(scope) : scope
    end

    def uploader_policy_for(mount)
      uploader_class = mount.uploader_class
      uploader_class.archive_storage_policy if uploader_class.respond_to?(:archive_storage_policy)
    rescue NameError
      nil
    end

    def policy_for(record, mount, uploader)
      mount.policy ||
        ArchiveStorage.policy_for_mount(record.class, mount.mounted_as) ||
        ArchiveStorage.policy_for_uploader(uploader)
    end

    def candidate_for_uploader(record, mount, uploader, identifier, policy)
      storage_key = uploader.store_path(identifier)
      current_storage = ArchiveStorage.registry.current_storage_for(
        uploader,
        identifier: identifier,
        storage_key: storage_key,
        default: policy.primary_storage_key
      )
      now = Time.now
      metadata = source_metadata_for(policy, record, current_storage, storage_key, now: now)
      target_rule = policy.target_rule_for(record, now: now, byte_size: metadata&.byte_size)
      return nil unless target_rule

      target_storage = target_rule.storage_key
      return nil if current_storage.to_sym == target_storage.to_sym

      Candidate.new(
        record: record,
        mounted_as: mount.mounted_as,
        uploader: uploader,
        identifier: identifier,
        storage_key: storage_key,
        source_storage_key: storage_key,
        target_storage_key: storage_key,
        current_storage: current_storage,
        target_storage: target_storage,
        byte_size: metadata&.byte_size,
        content_type: metadata&.content_type
      )
    end

    def uploaders_for(uploader, policy)
      uploaders = [uploader]
      return uploaders unless uploader.respond_to?(:versions)

      version_names = policy.selected_versions
      version_names ||= uploader.versions.keys if policy.include_versions
      return uploaders unless version_names

      version_names.each do |name|
        next unless uploader.versions.key?(name.to_sym)
        next if uploader.respond_to?(:version_active?) && !uploader.version_active?(name)

        uploaders << uploader.versions.fetch(name.to_sym)
      end

      uploaders
    end

    def too_young?(record)
      return false unless older_than

      timestamp = record.created_at if record.respond_to?(:created_at)
      timestamp && timestamp > Time.now - older_than
    end

    def identifier_for(record, uploader, mount)
      return uploader.identifier if uploader.respond_to?(:identifier) && uploader.identifier
      return record.public_send(mount.mounted_as) if record.respond_to?(mount.mounted_as)

      nil
    end

    def estimate_metadata(source_storage, storage_key)
      return nil unless estimate_sizes

      ArchiveStorage.adapter(source_storage).head(storage_key)
    rescue StandardError
      nil
    end

    def source_metadata_for(policy, record, source_storage, storage_key, now:)
      return estimate_metadata(source_storage, storage_key) if estimate_sizes
      return nil unless policy.requires_byte_size_for?(record, now: now)

      ArchiveStorage.adapter(source_storage).head(storage_key)
    rescue StandardError
      nil
    end
  end
end
