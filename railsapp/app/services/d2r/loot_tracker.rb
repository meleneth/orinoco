# frozen_string_literal: true

require "set"

module D2r
  # Confirm labels over consecutive frames. Keep unique sightings for the
  # current game so a hidden label or a return visit cannot repeat the event.
  class LootTracker
    RUNES = %w[El Eld Tir Nef Eth Ith Tal Ral Ort Thul Amn Sol Shael Dol Hel Io Lum
      Ko Fal Lem Pul Um Mal Ist Gul Vex Ohm Lo Sur Ber Jah Cham Zod].freeze

    def initialize(confirmations: 2)
      @confirmations = confirmations
      @counts = Hash.new(0)
      @visible = {}
      @unique_sightings = {}
      @area = nil
    end

    def observe(labels, observed_at:, area: nil, new_game: false)
      if new_game
        @unique_sightings.clear
        @counts.clear
        @visible.clear
        @area = nil
      end

      if area && area != @area
        if @area
          @counts.clear
        elsif (unlocated = @unique_sightings.delete(nil))
          @unique_sightings[area] = unlocated
        end
        @area = area
      end
      seen_uniques = (@unique_sightings[@area] ||= Set.new)
      current = {}
      labels.each do |label|
        key = normalize(label)
        current[key] ||= label if key
      end
      @counts.keys.each { |key| @counts.delete(key) unless current.include?(key) }
      @visible.keys.each { |key| @visible.delete(key) unless current.include?(key) }
      current.filter_map do |key, label|
        kind, name = key.split(":", 2)
        next if kind == "unique" && seen_uniques.include?(name)

        @counts[key] += 1
        next if @counts[key] < @confirmations || @visible[key]

        if kind == "rune"
          @visible[key] = true
          name = "#{name} Rune"
        else
          seen_uniques.add(name)
          name = label.fetch("name").to_s.strip.gsub(/\s+/, " ")
        end
        { "type" => "d2r.loot.#{kind}.sighted", "payload" => { "name" => name, "observed_at" => observed_at, "source" => "ground_label", "confidence" => label.fetch("confidence", "candidate") } }
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
        return "unique:#{value.downcase.tr("’", "'")}"
      end
      nil
    end
  end
end
