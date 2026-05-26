# frozen_string_literal: true

module ArchiveStorage
    class PlanResult
      attr_accessor :uploader_name, :destination
      attr_reader :candidates, :byte_size, :by_model

      def initialize(uploader_name: nil, destination: nil)
        @uploader_name = uploader_name
        @destination = destination
        @candidates = 0
        @byte_size = 0
        @by_model = Hash.new { |hash, key| hash[key] = { count: 0, byte_size: 0 } }
      end

      def add(candidate)
        @candidates += 1
        @byte_size += candidate.byte_size.to_i
        row = by_model[candidate.record.class.name]
        row[:count] += 1
        row[:byte_size] += candidate.byte_size.to_i
      end

      def to_text
        lines = []
        lines << "ArchiveStorage Migration Plan"
        lines << ""
        lines << "Uploader: #{uploader_name || "all registered uploaders"}"
        lines << "Candidates: #{candidates}"
        lines << "Estimated size: #{format_bytes(byte_size)}"
        lines << ""

        if by_model.any?
          lines << "By model:"
          by_model.each do |model, stats|
            lines << "- #{model}: #{stats[:count]} files, #{format_bytes(stats[:byte_size])}"
          end
          lines << ""
        end

        lines << "Destination: #{destination}" if destination
        lines << "No files were moved."
        lines.join("\n")
      end

      private

      def format_bytes(value)
        units = %w[B KB MB GB TB PB]
        size = value.to_f
        unit = units.shift

        while size >= 1024 && units.any?
          size /= 1024.0
          unit = units.shift
        end

        "#{format("%.2f", size)} #{unit}"
      end
    end
end
