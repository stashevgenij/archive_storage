# frozen_string_literal: true

module ArchiveStorage
  class StorageConfig
    attr_accessor :name,
                  :provider,
                  :endpoint,
                  :bucket,
                  :access_key_id,
                  :secret_access_key,
                  :region,
                  :path_style,
                  :public,
                  :public_host,
                  :root_path,
                  :base_url,
                  :adapter,
                  :options

    def initialize(name)
      @name = name.to_sym
      @provider = :s3
      @region = "us-east-1"
      @path_style = false
      @public = false
      @options = {}
    end

    def path_style?
      !!path_style
    end

    def public?
      !!public
    end
  end
end
