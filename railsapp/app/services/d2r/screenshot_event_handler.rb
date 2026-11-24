# frozen_string_literal: true

require "base64"
require "tempfile"
require_relative "fast_classifier"
require_relative "hud_reader"
require_relative "hud_area_reader"
require_relative "hud_tracker"
require_relative "loot_tracker"
require_relative "ground_label_reader"
require_relative "state_tracker"
require_relative "character_sheet_reader"
require_relative "character_tracker"
require_relative "character_creation_reader"
require_relative "character_menu_reader"
require_relative "character_menu_tracker"
require_relative "experience_bar_reader"
require_relative "experience_bar_tracker"

module D2r
  class ScreenshotEventHandler
    DATA_URI_PATTERN = %r{\Adata:image/(?<format>[a-zA-Z0-9.+-]+);base64,(?<data>.+)\z}m

    def initialize(config_reader:, classifier: FastClassifier.new, tracker: StateTracker.new,
      hud_reader: HudReader.new, hud_area_reader: HudAreaReader.new, hud_tracker: HudTracker.new,
      ground_label_reader: GroundLabelReader.new, loot_tracker: LootTracker.new, gate: nil, presence: nil,
      character_reader: nil, character_tracker: CharacterTracker.new,
      character_creation_reader: CharacterCreationReader.new, character_menu_reader: CharacterMenuReader.new,
      character_menu_tracker: CharacterMenuTracker.new, xp_reader: ExperienceBarReader.new,
      xp_tracker: ExperienceBarTracker.new)
      @config_reader = config_reader
      @classifier = classifier
      @tracker = tracker
      @hud_reader = hud_reader
      @hud_area_reader = hud_area_reader
      @hud_tracker = hud_tracker
      @ground_label_reader = ground_label_reader
      @loot_tracker = loot_tracker
      @gate = gate
      @presence = presence
      @character_reader = character_reader
      @character_tracker = character_tracker
      @character_creation_reader = character_creation_reader
      @character_menu_reader = character_menu_reader
      @character_menu_tracker = character_menu_tracker
      @xp_reader = xp_reader
      @xp_tracker = xp_tracker
    end

    def call(event, context)
      config = @config_reader.call
      return :disabled unless config.enabled?

      source_name = config.screenshot_source_name.to_s.strip
      return :missing_source if source_name.empty?
      return :ignored_source unless event.payload_value("sourceName").to_s == source_name

      classification, hud, loot, character_changes = with_screenshot_file(event.payload) do |path|
        result = @classifier.call(path).to_h
        active = !@presence || @presence.observe(source_name, result)
        unless active
          @xp_tracker.reset_sample
          next [ result, nil, nil ]
        end

        hud_reading = @hud_reader.call(path).except("area")
        # Bitmap references are approximate and can map any unseen/blank label
        # to the nearest Catacombs fixture. Require a known OCR heading for
        # area changes; bitmap features still supply difficulty/terror zones.
        inferred_area = @hud_area_reader.call(path)
        if inferred_area
          hud_reading["area"] = inferred_area
          # D2R omits the difficulty row in Normal games; Nightmare and Hell
          # render an explicit row which HudReader recognizes independently.
          hud_reading["difficulty"] ||= "Normal"
        end
        screen = result.dig("signals", "screen", "state")
        left_panel = result.dig("signals", "left_panel", "state")
        right_panel = result.dig("signals", "right_panel", "state")
        tooltip = result.dig("signals", "tooltip", "state")
        gameplay_screen = %w[gameplay area_banner boss_visible boss_dead].include?(screen)
        ground_labels_visible = gameplay_screen &&
          !%w[stash_runes stash_other quest_log].include?(left_panel) && right_panel != "inventory" &&
          (!tooltip || %w[none unknown].include?(tooltip))
        labels = ground_labels_visible ? @ground_label_reader.call(path) : []
        character_changes = if screen == "character_creation"
          @character_tracker.reset
          @character_menu_tracker.observe_creation(@character_creation_reader.call(path))
        elsif %w[character_select game_creation].include?(screen)
          @character_tracker.reset
          @character_menu_tracker.observe_selected(@character_menu_reader.call(path, screen:))
        elsif @character_reader && left_panel == "character"
          @character_menu_tracker.reset
          @character_tracker.observe(@character_reader.call(path))
        else
          @character_menu_tracker.reset unless %w[character_creation character_select game_creation].include?(screen)
          []
        end
        prior_level = @xp_tracker.level
        character_changes.each do |change|
          @xp_tracker.seed(change.fetch("payload")) if %w[d2r.character.selected d2r.character.observed].include?(change.fetch("type"))
        end
        character_changes.reject! do |change|
          change.fetch("type") == "d2r.level.changed" && change.dig("payload", "level") == prior_level
        end
        fill = gameplay_screen ? @xp_reader.call(path) : nil
        character_changes.concat(@xp_tracker.observe(fill, observed_at: event.occurred_at))
        [ result, hud_reading, labels, character_changes ]
      end
      return :standby if hud.nil?

      events = @tracker.observe(classification, observed_at: event.occurred_at)
      events.concat(@hud_tracker.observe(hud, observed_at: event.occurred_at))
      events.concat(@loot_tracker.observe(loot, observed_at: event.occurred_at))
      events.concat(character_changes || [])
      events.each do |change|
        payload = change.fetch("payload")
        if change.fetch("type") == "d2r.game.started"
          payload = payload.merge(
            hud.slice("area", "difficulty", "terror_zones"),
            "screen" => classification.dig("signals", "screen", "state")
          )
        end
        context.publish(
          change.fetch("type"),
          payload.merge(
            "screenshot" => screenshot_metadata(event),
            "classification" => classification.fetch("signals")
          ),
          correlation: event.correlation
        )
      end
      events.empty? ? :unchanged : :changed
    ensure
      @gate&.complete!(event.correlation["request_id"])
    end

    private

    def with_screenshot_file(payload)
      format = payload.fetch("imageFormat", "jpg").to_s
      bytes = decode_image_data(payload.fetch("imageData"))
      Tempfile.create([ "d2r-observer-", ".#{format}" ]) do |file|
        file.binmode
        file.write(bytes)
        file.flush
        yield file.path
      end
    end

    def decode_image_data(value)
      raw = value.to_s
      encoded = raw[DATA_URI_PATTERN, :data] || raw
      Base64.strict_decode64(encoded)
    rescue ArgumentError => e
      raise ArgumentError, "invalid screenshot imageData: #{e.message}"
    end

    def screenshot_metadata(event)
      %w[sourceName activeSceneName imageFormat imageWidth imageHeight captureStartedAt captureCompletedAt captureDurationMs].to_h do |key|
        [ key, event.payload_value(key) ]
      end.compact
    end
  end
end
