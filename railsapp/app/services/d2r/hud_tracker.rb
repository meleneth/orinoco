# frozen_string_literal: true

module D2r
  class HudTracker
    EVENT_TYPES = {
      "area" => "d2r.area.changed",
      "difficulty" => "d2r.difficulty.changed",
      "terror_zones" => "d2r.terror_zones.changed"
    }.freeze

    def initialize(confirmations: 2)
      @confirmations = Integer(confirmations)
      @candidates = {}
      @candidate_counts = Hash.new(0)
      @stable = {}
    end

    def observe(reading, observed_at:)
      EVENT_TYPES.filter_map do |field, type|
        value = reading[field]
        next if value.nil? || value == ""

        if @candidates[field] == value
          @candidate_counts[field] += 1
        else
          @candidates[field] = value
          @candidate_counts[field] = 1
        end
        default = [] if field == "terror_zones"
        next if @candidate_counts[field] < @confirmations || @stable.fetch(field, default) == value

        previous = @stable[field]
        @stable[field] = value
        { "type" => type, "payload" => { field => value, "previous" => previous, "observed_at" => observed_at } }
      end
    end

    def reset_game
      %w[difficulty terror_zones].each do |field|
        @candidates.delete(field)
        @candidate_counts.delete(field)
        @stable.delete(field)
      end
    end
  end
end
