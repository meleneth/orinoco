# frozen_string_literal: true

module D2r
  # Confirm named labels over consecutive frames rather than emitting the
  # same ground item once per screenshot. A disappearance clears the sighting.
  class LootTracker
    RUNES = %w[El Eld Tir Nef Eth Ith Tal Ral Ort Thul Amn Sol Shael Dol Hel Io Lum
      Ko Fal Lem Pul Um Mal Ist Gul Vex Ohm Lo Sur Ber Jah Cham Zod].freeze

    def initialize(confirmations: 2)
      @confirmations = confirmations
      @counts = Hash.new(0)
      @visible = {}
    end

    def observe(labels, observed_at:)
      current = labels.filter_map { |label| normalize(label) }.uniq
      @counts.keys.each { |key| @counts.delete(key) unless current.include?(key) }
      @visible.keys.each { |key| @visible.delete(key) unless current.include?(key) }
      current.filter_map do |key|
        @counts[key] += 1
        next if @counts[key] < @confirmations || @visible[key]

        @visible[key] = true
        kind, name = key.split(":", 2)
        original = labels.find { |label| normalize(label) == key }
        type = kind == "rune" ? "d2r.loot.rune.sighted" : "d2r.loot.unique.sighted"
        { "type" => type, "payload" => { "name" => name, "observed_at" => observed_at, "source" => "ground_label", "confidence" => original.fetch("confidence", "candidate") } }
      end
    end

    private

    def normalize(label)
      value = label.fetch("name").to_s.strip.gsub(/\s+/, " ")
      return if value.empty?
      if label["kind"] == "rune"
        rune = value.delete_suffix(" Rune")
        return "rune:#{rune}" if RUNES.include?(rune)
      elsif label["kind"] == "unique" && value.length >= 3
        return "unique:#{value}"
      end
      nil
    end
  end
end
