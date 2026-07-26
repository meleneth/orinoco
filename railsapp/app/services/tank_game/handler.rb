# frozen_string_literal: true

require_relative "command_parser"
require_relative "engine"
require_relative "state_store"
require_relative "tick_scheduler"

module TankGame
  class Handler
    SOURCE = "tank_game"

    def initialize(redis:, publisher:, broadcaster: Turbo::StreamsChannel, engine: Engine.new, config_reader: -> { AffordanceConfig.fetch!(:tank_game) }, inventory_reader: nil, external_base_url: nil, tick_scheduler: nil, toast_broadcaster: nil, obs_bridge_available: -> { true })
      @store = StateStore.new(redis: redis)
      @publisher = publisher
      @broadcaster = broadcaster
      @engine = engine
      @config_reader = config_reader
      @inventory_reader = inventory_reader
      @external_base_url = external_base_url
      @tick_scheduler = tick_scheduler
      @toast_broadcaster = toast_broadcaster
      @obs_bridge_available = obs_bridge_available
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
      when :demo
                     start_game(state: state, message: message, config: config, demo: true)
      when :signup
                     engine.add_player(state: state, message: message)
      when :aim
                     engine.update_aim(state: state, message: message, angle: command.args.fetch("angle"), power: command.args.fetch("power"))
      when :weapon
                     engine.update_weapon(state: state, message: message, weapon: command.args.fetch("weapon"))
      else
                     state
      end

      if next_state != state
        persist_and_broadcast(next_state)
        broadcast_chat_toast(command, message, next_state)
      end
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

      next_state = if state["demo"]
                     engine.begin_demo(state: state, previous_scene_name: previous_scene, config: config_hash)
      else
                     engine.begin_signup(state: state, previous_scene_name: previous_scene, config: config_hash)
      end
      publish_setup_commands(next_state, config_hash)
      persist_and_broadcast(next_state)
      schedule_next_tick(next_state)
      broadcast_setup_toast(next_state)
      :handled
    end

    def handle_tick_event(event)
      state = store.read
      return :ignored unless event.payload["round_id"].to_s == state["round_id"].to_s

      next_state = engine.tick(state: state, config: config_hash)
      return :idle if next_state == state

      publish_restore_command(next_state) if state["phase"] == "ending" && next_state["phase"] == "ended"
      persist_and_broadcast(next_state)
      schedule_next_tick(next_state)
      broadcast_tick_toast(previous_state: state, current_state: next_state)
      :handled
    end

    private

    attr_reader :store, :publisher, :broadcaster, :engine, :inventory_reader, :external_base_url, :tick_scheduler, :toast_broadcaster, :obs_bridge_available

    def start_game(state:, message:, config:, demo: false)
      return state unless authorized_starter?(message)
      return finish_setup_without_obs(state: state, config: config) if state["phase"] == "setup_pending" && !obs_bridge_connected?
      return state if %w[setup_pending signup active ending].include?(state["phase"])

      setup_state = if demo
                      engine.start_demo_setup(state: state, trigger: message, config: config)
      else
                      engine.start_setup(state: state, trigger: message, config: config)
      end
      return finish_setup_without_obs(state: setup_state, config: config) unless obs_bridge_connected?

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

    def finish_setup_without_obs(state:, config:)
      next_state = if state["demo"]
                     engine.begin_demo(state: state, previous_scene_name: "", config: config)
      else
                     engine.begin_signup(state: state, previous_scene_name: "", config: config)
      end.merge(
        "obs_setup" => "unavailable",
        "status" => overlay_only_status(state)
      )

      schedule_next_tick(next_state)
      broadcast_setup_toast(next_state)
      next_state
    end

    def overlay_only_status(state)
      state["demo"] ? "TankDemo active: 10 NPC tanks (OBS bridge unavailable; overlay only)" : "TankGame signup open (OBS bridge unavailable; overlay only)"
    end

    def obs_bridge_connected?
      obs_bridge_available.call
    rescue StandardError => e
      Rails.logger.warn("[tank-game] OBS bridge availability check failed: #{e.class}: #{e.message}")
      false
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
        publish_obs_request({ "requestType" => "CreateSceneItem", "requestData" => { "sceneName" => scene_name, "sourceName" => previous_scene, "sceneItemEnabled" => true, "sceneItemTransform" => fullscreen_transform(config) } })
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
              "sceneItemEnabled" => true,
              "sceneItemTransform" => fullscreen_transform(config)
            }
          }
        )
      end
      publish_obs_request({ "requestType" => "SetInputSettings", "requestData" => { "inputName" => web_source_name, "inputSettings" => input_settings(config), "overlay" => true } })
      if previous_scene.present? && (background_scene_item = scene_item(scene_name, previous_scene))
        publish_obs_request(
          {
            "requestType" => "SetSceneItemTransform",
            "requestData" => {
              "sceneName" => scene_name,
              "sceneItemId" => background_scene_item.fetch("sceneItemId"),
              "sceneItemTransform" => fullscreen_transform(config)
            }
          }
        )
      end
      if (web_scene_item = scene_item(scene_name, web_source_name))
        publish_obs_request(
          {
            "requestType" => "SetSceneItemTransform",
            "requestData" => {
              "sceneName" => scene_name,
              "sceneItemId" => web_scene_item.fetch("sceneItemId"),
              "sceneItemTransform" => fullscreen_transform(config)
            }
          }
        )
      end
      publish_obs_request({ "requestType" => "SetCurrentProgramScene", "requestData" => { "sceneName" => scene_name } })
    end

    def broadcast_chat_toast(command, message, state)
      case command.type
      when :start
        broadcast_toast("#{display_name(message)} requested TankGame", tone: "info", title: "TankGame")
      when :demo
        broadcast_toast("#{display_name(message)} requested TankDemo", tone: "info", title: "TankDemo")
      when :signup
        broadcast_toast("#{display_name(message)} joined TankGame", tone: "success", title: "TankGame")
      when :aim
        player = player_for_state(state, message)
        broadcast_toast("#{display_name(message)} aim #{player.fetch("angle", command.args.fetch("angle"))} / #{player.fetch("power", command.args.fetch("power"))}", tone: "info", title: "TankGame")
      when :weapon
        player = player_for_state(state, message)
        broadcast_toast("#{display_name(message)} selected weapon #{player.fetch("weapon", command.args.fetch("weapon"))}", tone: "info", title: "TankGame")
      end
    end

    def broadcast_setup_toast(state)
      if state["demo"]
        broadcast_toast("TankDemo live: #{Array(state["players"]).length} NPC tanks", tone: "warning", title: "TankDemo")
      else
        broadcast_toast("Signup open for TankGame", tone: "success", title: "TankGame")
      end
    end

    def broadcast_tick_toast(previous_state:, current_state:)
      if volley_changed?(previous_state, current_state)
        shots = Array(current_state.dig("last_volley", "shots")).length
        broadcast_toast("Volley fired: #{shots} shots", tone: "warning", title: current_state["demo"] ? "TankDemo" : "TankGame")
      end

      if previous_state["phase"] != current_state["phase"]
        case current_state["phase"]
        when "active"
          broadcast_toast("TankGame live: #{Array(current_state["players"]).length} tanks", tone: "success", title: "TankGame")
        when "ending"
          broadcast_toast(current_state["status"], tone: "success", title: "TankGame")
        when "ended"
          broadcast_toast("TankGame overlay restored", tone: "info", title: "TankGame")
        end
      end
    end

    def volley_changed?(previous_state, current_state)
      previous_state.dig("last_volley", "id") != current_state.dig("last_volley", "id") && current_state.dig("last_volley", "id").present?
    end

    def display_name(message)
      message.display_name.to_s.presence || login_name(message)
    end

    def login_name(message)
      message.name.to_s.downcase
    end

    def player_for_state(state, message)
      Array(state["players"]).find { |player| player["login"] == login_name(message) } || {}
    end

    def broadcast_toast(message, tone:, title:)
      return unless toast_broadcaster

      toast_broadcaster.broadcast!(message: message, tone: tone, title: title)
    rescue StandardError => e
      Rails.logger.warn("[tank-game] toast broadcast failed: #{e.class}: #{e.message}")
    end

    def schedule_next_tick(state)
      return unless tick_scheduler

      case state["phase"]
      when "signup"
        schedule_tick_at(state, state["signup_ends_at"], "signup_closed")
      when "active"
        schedule_tick_at(state, next_active_tick_at(state), "combat_tick")
      when "ending"
        schedule_tick_at(state, state["restore_at"], "restore_scene")
      end
    end

    def next_active_tick_at(state)
      candidates = [ state["next_fire_at"], state["round_ends_at"] ].filter_map { |value| parse_time(value) }
      candidates.min&.iso8601
    end

    def schedule_tick_at(state, timestamp, reason)
      run_at = parse_time(timestamp)
      return unless run_at

      tick_scheduler.schedule!(state, run_at: run_at, reason: reason)
    rescue StandardError => e
      Rails.logger.warn("[tank-game] failed to schedule #{reason}: #{e.class}: #{e.message}")
    end

    def parse_time(value)
      return nil if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
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
        broadcaster.broadcast_replace_to(
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

    def fullscreen_transform(config)
      {
        "positionX" => 0,
        "positionY" => 0,
        "boundsType" => "OBS_BOUNDS_STRETCH",
        "boundsWidth" => positive_integer(config["width"], 1920),
        "boundsHeight" => positive_integer(config["height"], 1080)
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
      scene_item(scene_name, source_name).present?
    end

    def scene_item(scene_name, source_name)
      return nil unless inventory_reader

      inventory_reader.scene_items(scene_name).find { |item| item["sourceName"] == source_name && item["sceneItemId"].present? }
    rescue StandardError
      nil
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
