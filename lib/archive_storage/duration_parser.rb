# frozen_string_literal: true

module ArchiveStorage
    class DurationParser
      UNITS = {
        "s" => 1,
        "m" => 60,
        "h" => 60 * 60,
        "d" => 24 * 60 * 60,
        "w" => 7 * 24 * 60 * 60,
        "mo" => 30 * 24 * 60 * 60,
        "y" => 365 * 24 * 60 * 60
      }.freeze

      def self.parse(value)
        return nil if value.nil? || value == ""
        return value if value.is_a?(Numeric)
        return value.to_i if value.respond_to?(:to_i) && !value.is_a?(String)

        match = value.to_s.strip.match(/\A(\d+)\s*(mo|[smhdwy])\z/i)
        raise ArgumentError, "invalid duration #{value.inspect}" unless match

        match[1].to_i * UNITS.fetch(match[2].downcase)
      end
    end
end
