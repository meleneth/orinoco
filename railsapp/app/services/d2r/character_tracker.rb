# frozen_string_literal: true

module D2r
  # Confirms every field independently. XP churn cannot block attributes, and
  # missing OCR output never replaces a previously confirmed value.
  class CharacterTracker
    IDENTITY_FIELDS = %w[name character_class].freeze

    def initialize(confirmations: 2)
      @confirmations = Integer(confirmations)
      @candidates = {}
      @candidate_counts = Hash.new(0)
      @confirmed = {}
    end

    def observe(reading)
      changes = confirm(flatten(reading))
      return [] if changes.empty? || IDENTITY_FIELDS.any? { |field| @confirmed[field].nil? }

      payload = nested(@confirmed).merge("changed_fields" => changes.keys.sort)
      events = [ { "type" => "d2r.character.observed", "payload" => payload } ]
      if changes.key?("level")
        events << {
          "type" => "d2r.level.changed",
          "payload" => payload.slice("name", "character_class", "level").merge("previous" => changes.dig("level", "previous"))
        }
      end
      if changes.key?("experience")
        previous = changes.dig("experience", "previous")
        current = @confirmed.fetch("experience")
        events << {
          "type" => "d2r.experience.changed",
          "payload" => payload.slice("name", "character_class", "level", "experience").merge(
            "previous" => previous,
            "delta" => previous && current >= previous ? current - previous : nil
          )
        }
      end
      events
    end

    def reset
      @candidates.clear
      @candidate_counts.clear
      @confirmed.clear
    end

    private

    def flatten(reading)
      reading.each_with_object({}) do |(field, value), result|
        if field == "stats"
          value.each { |name, number| result["stats.#{name}"] = number unless number.nil? }
        else
          result[field] = value unless value.nil?
        end
      end
    end

    def confirm(reading)
      reading.each_with_object({}) do |(field, value), changes|
        if @candidates[field] == value
          @candidate_counts[field] += 1
        else
          @candidates[field] = value
          @candidate_counts[field] = 1
        end
        next if @candidate_counts[field] < @confirmations || @confirmed[field] == value

        changes[field] = { "previous" => @confirmed[field], "current" => value }
        @confirmed[field] = value
      end
    end

    def nested(flat)
      result = {}
      flat.each do |field, value|
        if field.start_with?("stats.")
          (result["stats"] ||= {})[field.delete_prefix("stats.")] = value
        else
          result[field] = value
        end
      end
      result
    end
  end
end
