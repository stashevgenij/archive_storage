# frozen_string_literal: true

module ArchiveStorage
  class MountConfig
    attr_reader :model, :mounted_as, :uploader, :policy

    def initialize(model, mounted_as, uploader: nil, policy: nil)
      @model = model
      @mounted_as = mounted_as.to_sym
      @uploader = uploader
      @policy = policy
    end

    def model_class
      constantize(model)
    end

    def model_name
      model.respond_to?(:name) ? model.name : model.to_s
    end

    def uploader_class
      constantize(uploader) if uploader
    end

    def matches_model?(value, mounted_as_value = nil)
      model_matches = model_name == (value.respond_to?(:name) ? value.name : value.to_s)
      mount_matches = mounted_as_value.nil? || mounted_as == mounted_as_value.to_sym

      model_matches && mount_matches
    end

    def matches_uploader?(value)
      return true if value.nil?

      expected = uploader_class || value
      expected.to_s == value.to_s ||
        (expected.respond_to?(:name) && expected.name == value.to_s)
    end

    private

    def constantize(value)
      return value if value.respond_to?(:name) && value.respond_to?(:all)
      return value if value.is_a?(Class)

      value.to_s.split("::").inject(Object) { |namespace, name| namespace.const_get(name) }
    end
  end
end
