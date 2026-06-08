# frozen_string_literal: true

module ArchiveStorage
  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  NotFoundError = Class.new(Error)
  VerificationError = Class.new(Error)
  RegistryUnavailableError = Class.new(Error)
  MaxByteSizeExceededError = Class.new(Error)
end
