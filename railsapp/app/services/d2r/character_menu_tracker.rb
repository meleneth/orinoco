# frozen_string_literal: true

module D2r
  class CharacterMenuTracker
    def initialize(confirmations: 2)
      @confirmations = Integer(confirmations)
      @candidates = {}
      @counts = Hash.new(0)
      @confirmed = {}
    end

    def observe_creation(reading)
      observe(reading, "d2r.character.creation.draft_observed")
    end

    def observe_selected(reading)
      observe(reading, "d2r.character.selected")
    end

    def reset
      @candidates.clear
      @counts.clear
      @confirmed.clear
    end

    private

    def observe(reading, type)
      return [] unless reading["name"].present? && reading["character_class"].present?

      if reading == @candidates[type]
        @counts[type] += 1
      else
        @candidates[type] = reading
        @counts[type] = 1
      end
      return [] if @counts[type] < @confirmations || reading == @confirmed[type]

      @confirmed[type] = reading
      [ { "type" => type, "payload" => reading } ]
    end
  end
end
