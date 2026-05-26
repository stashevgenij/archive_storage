# frozen_string_literal: true

module ArchiveStorage
  class MigrationRate
    attr_reader :files

    def initialize(files)
      @files = Integer(files)
      raise ArgumentError, "migration rate must be greater than zero" unless files.positive?
    end

    def max_files_per_run
      files
    end
  end
end
