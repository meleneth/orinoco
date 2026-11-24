# frozen_string_literal: true

module D2r
  class CharacterTracker
    def initialize
      @candidate = nil
      @confirmed = nil
    end

    def observe(reading)
      return [] unless reading["name"] && reading["character_class"]
      unless reading == @candidate
        @candidate = reading
        return []
      end
      return [] if reading == @confirmed

      @confirmed = reading
      [{ "type" => "d2r.character.observed", "payload" => reading }]
    end

    def reset
      @candidate = @confirmed = nil
    end
  end
end
