# frozen_string_literal: true

module D2r
  class CharacterMenuTracker
    def initialize(confirmations: 2)
      @confirmations = Integer(confirmations)
      @candidate = nil
      @count = 0
      @confirmed = nil
    end

    def observe_creation(reading)
      observe(reading, "d2r.character.creation.draft_observed")
    end

    def reset
      @candidate = @confirmed = nil
      @count = 0
    end

    private

    def observe(reading, type)
      return [] unless reading["name"].present? && reading["character_class"].present?

      if reading == @candidate
        @count += 1
      else
        @candidate = reading
        @count = 1
      end
      return [] if @count < @confirmations || reading == @confirmed

      @confirmed = reading
      [ { "type" => type, "payload" => reading } ]
    end
  end
end
