# frozen_string_literal: true

require_relative "command_parser"
require_relative "engine"
require_relative "state_store"

module TankGame
  class Handler
    SOURCE = "tank_game"

    def initialize(redis:, publisher:, broadcaster: Turbo::StreamsChannel, engine: Engine.new, config_reader: -> { AffordanceConfig.fetch!(:tank_game) }, inventory_reader: nil, external_base_url: nil)
      @store = StateStore.new(redis: redis)
      @publisher = publisher
      @broadcaster = broadcaster
      @engine = engine
      @config_reader = config_reader
      @inventory_reader = inventory_reader
      @external_base_url = external_base_url
    end

    def handle_chat_event(event)
      config = config_hash
      return :disabled unless enabled?(config)

      message = TwitchChatBridge::Message.from_json(JSON.generate(event.payload))
      command = CommandParser.new(config: config).parse(message.txt)
      return :ignored unless command

      state = store.read
      next_state = case command.type
      when :start
                     start_game(state: state, message: message, config: config)
      when :signup
                     engine.add_player(state: state, message: message)
      when :aim
                     engine.update_aim(state: state, message: message, angle: command.args.fetch("angle"), power: command.args.fetch("power"))
      when :weapon
                     engine.update_weapon(state: state, message: message, weapon: command.args.fetch("weapon"))
      else
                     state
      end

      persist_and_broadcast(next_state) unless next_state == state
      :handled
    end

    def handle_obs_result(event)
      state = store.read
      return :ignored unless state["phase"] == "setup_pending"
      return :ignored unless event.correlation["request_id"].to_s == state["setup_request_id"].to_s

      previous_scene = event.payload.dig("response", "currentProgramSceneName").to_s
      previous_scene = event.payload.dig("response", "current_program_scene_name").to_s if previous_scene.empty?
      previous_scene = event.payload.dig("request", "requestData", "sceneName").to_s if previous_scene.empty?
      previous_scene = "" if previous_scene == config_hash.fetch("scene_name", "TankGame")

      next_state = engine.begin_signup(state: state, previous_scene_name: previous_scene, config: config_hash)
      publish_setup_commands(next_state, config_hash)
      persist_and_broadcast(next_state)
      :handled
    end

    def tick
      state = store.read
      next_state = engine.tick(state: state, config: config_hash)
      return :idle if next_state == state

      publish_restore_command(next_state) if state["phase"] == "ending" && next_state["phase"] == "ended"
      persist_and_broadcast(next_state)
      :handled
    end

    private

    attr_reader :store, :publisher, :broadcaster, :engine, :inventory_reader, :external_base_url

    def start_game(state:, message:, config:)
      return state unless authorized_starter?(message)
      return state if %w[setup_pending signup active ending].include?(state["phase"])

      setup_state = engine.start_setup(state: state, trigger: message, config: config)
      publish_obs_request(
        {
          "requestType" => "GetCurrentProgramScene",
          "requestData" => {}
        },
        correlation: { "request_id" => setup_state.fetch("setup_request_id"), "round_id" => setup_state.fetch("round_id") },
        reply_topic: Orinoco::Messaging::Names::OBS_COMMAND_RESULT_TOPIC
      )
      setup_state
    end

    def authorized_starter?(message)
      tags = message.tags || {}
      return true if truthy?(tags[:mod] || tags["mod"])

      badges = tags[:badges] || tags["badges"] || []
      Array(badges).any? { |badge| %w[broadcaster moderator].include?(badge.to_s) }
    end

    def publish_setup_commands(state, config)
      scene_name = config.fetch("scene_name", "TankGame")
      web_source_name = config.fetch("web_source_name", "TankGameWebView")
      previous_scene = state["previous_scene_name"].to_s

      publish_obs_request({ "requestType" => "CreateScene", "requestData" => { "sceneName" => scene_name } }) unless scene_present?(scene_name)
      if previous_scene.present? && !scene_item_present?(scene_name, previous_scene)
        publish_obs_request({ "requestType" => "CreateSceneItem", "requestData" => { "sceneName" => scene_name, "sourceName" => previous_scene, "sceneItemEnabled" => true } })
      end
      unless scene_item_present?(scene_name, web_source_name)
        publish_obs_request(
          {
            "requestType" => "CreateInput",
            "requestData" => {
              "sceneName" => scene_name,
              "inputName" => web_source_name,
              "inputKind" => "browser_source",
              "inputSettings" => input_settings(config),
              "sceneItemEnabled" => true
            }
          }
        )
      end
      publish_obs_request({ "requestType" => "SetInputSettings", "requestData" => { "inputName" => web_source_name, "inputSettings" => input_settings(config), "overlay" => true } })
      publish_obs_request({ "requestType" => "SetCurrentProgramScene", "requestData" => { "sceneName" => scene_name } })
    end

    def publish_restore_command(state)
      scene_name = state["previous_scene_name"].to_s
      return if scene_name.empty?

      publish_obs_request({ "requestType" => "SetCurrentProgramScene", "requestData" => { "sceneName" => scene_name } })
    end

    def publish_obs_request(request, correlation: {}, reply_topic: nil)
      payload = { "request" => request }
      payload["reply_topic"] = reply_topic if reply_topic
      publisher.publish("obs.command.requested", payload, source: SOURCE, correlation: correlation)
    end

    def persist_and_broadcast(state)
      store.write!(state)
      broadcast_state(state)
      state
    end

    def broadcast_state(state)
      Rails.application.reloader.wrap do
        broadcaster.broadcast_update_to(
          "tank_game:overlay",
          target: "tank_game_overlay",
          layout: false,
          renderable: TankGameOverlayComponent.new(state: state)
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[tank-game] overlay broadcast failed: #{e.class}: #{e.message}")
    end

    def input_settings(config)
      {
        "url" => "#{base_url}/tank_game/overlay",
        "width" => positive_integer(config["width"], 1920),
        "height" => positive_integer(config["height"], 1080),
        "shutdown" => false,
        "fps" => 60
      }
    end

    def base_url
      external_base_url.presence || ENV.fetch("ORINOCO_EXTERNAL_BASE_URL", "http://localhost:31050")
    end

    def scene_present?(scene_name)
      return false unless inventory_reader

      inventory_reader.scenes.any? { |scene| scene["sceneName"] == scene_name }
    rescue StandardError
      false
    end

    def scene_item_present?(scene_name, source_name)
      return false unless inventory_reader

      inventory_reader.scene_items(scene_name).any? { |item| item["sourceName"] == source_name }
    rescue StandardError
      false
    end

    def config_hash
      raw = @config_reader.call
      if raw.respond_to?(:config)
        raw.config.deep_stringify_keys
      else
        raw.to_h.deep_stringify_keys
      end
    end

    def enabled?(config)
      ActiveModel::Type::Boolean.new.cast(config.fetch("enabled", true))
    end

    def positive_integer(value, fallback)
      Integer(value).positive? ? Integer(value) : fallback
    rescue ArgumentError, TypeError
      fallback
    end

    def truthy?(value)
      value == true || value.to_s == "1" || value.to_s.casecmp?("true")
    end
  end
end
