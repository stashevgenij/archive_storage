# frozen_string_literal: true

module ArchiveStorage
  VerificationResult = Struct.new(
    :strategy,
    :matched_by,
    :source_metadata,
    :target_metadata,
    keyword_init: true
  )
end
