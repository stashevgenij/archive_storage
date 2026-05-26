# frozen_string_literal: true

module ArchiveStorage
  module Model
    def archive_storage_for(mounted_as, &block)
      raise ArgumentError, "archive_storage_for requires a block" unless block

      policy = PolicyBuilder.build(&block)
      uploader_class = archive_storage_uploader_for(mounted_as)

      ArchiveStorage.wire_carrierwave_uploader!(uploader_class)
      ArchiveStorage.register_mount(self, mounted_as, uploader: uploader_class, policy: policy)

      archive_storage_policies[mounted_as.to_sym] = policy
    end

    def archive_storage_policy_for(mounted_as)
      archive_storage_policies[mounted_as.to_sym]
    end

    def archive_storage_policies
      @archive_storage_policies ||= {}
    end

    private

    def archive_storage_uploader_for(mounted_as)
      if respond_to?(:uploaders) && uploaders[mounted_as.to_sym]
        uploaders[mounted_as.to_sym]
      else
        raise ConfigurationError, "cannot find CarrierWave uploader for #{name}##{mounted_as}"
      end
    end
  end
end
