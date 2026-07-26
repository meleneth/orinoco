# frozen_string_literal: true

require "securerandom"

module TankGame
  class Engine
    WIDTH = 1920
    HEIGHT = 1080
    GROUND_TOP = 575
    GROUND_BOTTOM = 880
    GRAVITY = 0.26
    TANK_RADIUS = 22

    WEAPONS = {
      1 => { "name" => "Shell", "damage" => 38, "radius" => 72, "speed" => 1.0, "cluster" => 0 },
      2 => { "name" => "Heavy", "damage" => 58, "radius" => 96, "speed" => 0.82, "cluster" => 0 },
      3 => { "name" => "Cluster", "damage" => 24, "radius" => 52, "speed" => 0.96, "cluster" => 3 }
    }.freeze

    def initialize(clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.uuid })
      @clock = clock
      @id_generator = id_generator
    end

    def start_setup(state:, trigger:, config:, request_id: nil)
      now = iso_now
      {
        "phase" => "setup_pending",
        "round_id" => id_generator.call,
        "setup_request_id" => request_id || id_generator.call,
        "triggered_by" => player_identity(trigger),
        "triggered_at" => now,
        "players" => [],
        "tanks" => [],
        "terrain" => [],
        "projectiles" => [],
        "explosions" => [],
        "winner" => nil,
        "status" => "Preparing TankGame scene...",
        "config" => public_config(config)
      }
    end

    def begin_signup(state:, previous_scene_name:, config:)
      now = clock.call
      state.merge(
        "phase" => "signup",
        "previous_scene_name" => previous_scene_name,
        "signup_started_at" => now.iso8601,
        "signup_ends_at" => (now + signup_seconds(config)).iso8601,
        "round_ends_at" => (now + max_round_seconds(config)).iso8601,
        "status" => "Type #{config.fetch("signup_command", "!signup")} to join TankGame"
      )
    end

    def add_player(state:, message:)
      return state unless state["phase"] == "signup"

      name = display_name(message)
      login = login_name(message)
      return state if Array(state["players"]).any? { |player| player["login"] == login }

      player = {
        "login" => login,
        "display_name" => name,
        "health" => 100,
        "active" => true,
        "angle" => 45.0,
        "power" => 55.0,
        "weapon" => 1,
        "damage_dealt" => 0,
        "signed_up_at" => iso_now
      }
      state.merge(
        "players" => Array(state["players"]) + [ player ],
        "status" => "#{name} joined TankGame"
      )
    end

    def update_aim(state:, message:, angle:, power:)
      update_player(state, message) do |player|
        player.merge(
          "angle" => clamp(angle.to_f, 0.0, 180.0).round(2),
          "power" => clamp(power.to_f, 1.0, 100.0).round(2)
        )
      end
    end

    def update_weapon(state:, message:, weapon:)
      return state unless WEAPONS.key?(weapon.to_i)

      update_player(state, message) { |player| player.merge("weapon" => weapon.to_i) }
    end

    def tick(state:, config:)
      case state["phase"]
      when "signup"
        signup_due?(state) ? activate_round(state, config: config) : state
      when "active"
        return finish_round(state, reason: "timeout") if round_timeout?(state)
        return finish_round(state, reason: "winner") if active_players(state).length <= 1

        fire_due?(state, config) ? fire_round(state, config: config) : state
      when "ending"
        ending_due?(state) ? state.merge("phase" => "ended", "status" => ended_status(state)) : state
      else
        state
      end
    end

    private

    attr_reader :clock, :id_generator

    def activate_round(state, config:)
      players = Array(state["players"])
      return state.merge("phase" => "ended", "status" => "TankGame cancelled: no players signed up") if players.empty?

      terrain = build_terrain(players.length)
      tanks = players.each_with_index.map do |player, index|
        x = tank_x(index, players.length)
        y = terrain_y(terrain, x)
        {
          "login" => player.fetch("login"),
          "x" => x.round(2),
          "y" => y.round(2),
          "turret_x" => x.round(2),
          "turret_y" => (y - TANK_RADIUS).round(2)
        }
      end
      now = clock.call
      state.merge(
        "phase" => "active",
        "terrain" => terrain,
        "tanks" => tanks,
        "next_fire_at" => now.iso8601,
        "last_fire_at" => nil,
        "status" => "TankGame active: #{players.length} tanks"
      )
    end

    def fire_round(state, config:)
      state = state.merge("projectiles" => [], "explosions" => [])
      active_players(state).each do |player|
        tank = tank_for(state, player.fetch("login"))
        next unless tank

        state = resolve_shot(state, shooter: player, tank: tank)
      end
      now = clock.call
      state = finish_round(state, reason: "winner") if active_players(state).length <= 1
      return state if state["phase"] == "ending"

      state.merge(
        "last_fire_at" => now.iso8601,
        "next_fire_at" => (now + fire_interval_seconds(config)).iso8601,
        "status" => "Volley fired at #{now.strftime("%H:%M:%S UTC")}"
      )
    end

    def resolve_shot(state, shooter:, tank:)
      weapon = WEAPONS.fetch(shooter.fetch("weapon", 1), WEAPONS.fetch(1))
      impacts = impacts_for(state, shooter: shooter, tank: tank, weapon: weapon)
      state = state.merge("projectiles" => Array(state["projectiles"]) + impacts.fetch(:paths))
      impacts.fetch(:explosions).each do |explosion|
        state = apply_explosion(state, explosion: explosion, shooter: shooter, weapon: weapon)
      end
      state
    end

    def impacts_for(state, shooter:, tank:, weapon:)
      angle = shooter.fetch("angle", 45).to_f * Math::PI / 180.0
      speed = shooter.fetch("power", 55).to_f * weapon.fetch("speed") * 0.42
      vx = Math.cos(angle) * speed
      vy = -Math.sin(angle) * speed
      x = tank.fetch("turret_x").to_f
      y = tank.fetch("turret_y").to_f
      path = []

      240.times do
        x += vx
        y += vy
        vy += GRAVITY
        path << { "x" => x.round(2), "y" => y.round(2) } if path.length < 30
        break if x < 0 || x > WIDTH || y > HEIGHT || y >= terrain_y(state.fetch("terrain", []), x)
      end

      impact = { "x" => clamp(x, 0, WIDTH).round(2), "y" => clamp(y, 0, HEIGHT).round(2), "radius" => weapon.fetch("radius"), "weapon" => shooter.fetch("weapon", 1) }
      explosions = [ impact ]
      if weapon.fetch("cluster").positive?
        explosions = [ -45, 0, 45 ].map do |offset|
          impact.merge("x" => clamp(impact.fetch("x") + offset, 0, WIDTH).round(2), "radius" => weapon.fetch("radius"))
        end
      end

      { paths: [ { "shooter" => shooter.fetch("login"), "points" => path } ], explosions: explosions }
    end

    def apply_explosion(state, explosion:, shooter:, weapon:)
      players = Array(state["players"]).map do |player|
        tank = tank_for(state, player.fetch("login"))
        next player unless player.fetch("active", true) && tank

        distance = Math.hypot(tank.fetch("x").to_f - explosion.fetch("x").to_f, tank.fetch("y").to_f - explosion.fetch("y").to_f)
        next player if distance > explosion.fetch("radius").to_f

        damage = ((1.0 - (distance / explosion.fetch("radius").to_f)) * weapon.fetch("damage")).round
        health = [ player.fetch("health", 100).to_i - damage, 0 ].max
        dealt = shooter.fetch("login") == player.fetch("login") ? 0 : damage
        if dealt.positive?
          shooter = shooter.merge("damage_dealt" => shooter.fetch("damage_dealt", 0).to_i + dealt)
        end
        player.merge("health" => health, "active" => health.positive?)
      end
      players = players.map { |player| player.fetch("login") == shooter.fetch("login") ? player.merge("damage_dealt" => shooter.fetch("damage_dealt", 0)) : player }
      state.merge(
        "players" => players,
        "explosions" => Array(state["explosions"]) + [ explosion ],
        "terrain" => deform_terrain(state.fetch("terrain", []), explosion)
      )
    end

    def finish_round(state, reason:)
      winner = choose_winner(state)
      state.merge(
        "phase" => "ending",
        "winner" => winner,
        "ended_at" => iso_now,
        "restore_at" => (clock.call + 5).iso8601,
        "end_reason" => reason,
        "status" => winner ? "#{winner.fetch("display_name")} wins TankGame" : "TankGame ended"
      )
    end

    def choose_winner(state)
      candidates = Array(state["players"])
      active = candidates.select { |player| player.fetch("active", true) }
      candidates = active unless active.empty?
      candidates.max_by { |player| [ player.fetch("health", 0).to_i, player.fetch("damage_dealt", 0).to_i, -candidates.index(player) ] }
    end

    def ended_status(state)
      winner = state["winner"]
      winner ? "TankGame complete: #{winner.fetch("display_name")} won" : "TankGame complete"
    end

    def update_player(state, message)
      return state unless %w[signup active].include?(state["phase"])

      login = login_name(message)
      changed = false
      players = Array(state["players"]).map do |player|
        next player unless player.fetch("login") == login

        changed = true
        yield player
      end
      changed ? state.merge("players" => players) : state
    end

    def build_terrain(player_count)
      points = []
      segments = [ 12, player_count * 2 ].max
      segments.times do |index|
        x = WIDTH * index / (segments - 1).to_f
        y = GROUND_TOP + ((Math.sin(index * 0.91) + 1.0) * 0.5 * (GROUND_BOTTOM - GROUND_TOP))
        points << { "x" => x.round(2), "y" => y.round(2) }
      end
      points
    end

    def deform_terrain(terrain, explosion)
      radius = explosion.fetch("radius").to_f * 0.55
      terrain.map do |point|
        dx = point.fetch("x").to_f - explosion.fetch("x").to_f
        distance = dx.abs
        next point if distance > radius

        point.merge("y" => clamp(point.fetch("y").to_f + ((1.0 - distance / radius) * 34), GROUND_TOP, HEIGHT - 40).round(2))
      end
    end

    def terrain_y(terrain, x)
      return GROUND_BOTTOM if terrain.empty?

      sorted = terrain.sort_by { |point| point.fetch("x").to_f }
      left, right = sorted.each_cons(2).find { |a, b| x >= a.fetch("x").to_f && x <= b.fetch("x").to_f }
      return sorted.first.fetch("y").to_f if left.nil? && x < sorted.first.fetch("x").to_f
      return sorted.last.fetch("y").to_f if left.nil?

      span = right.fetch("x").to_f - left.fetch("x").to_f
      ratio = span.zero? ? 0.0 : (x - left.fetch("x").to_f) / span
      left.fetch("y").to_f + ((right.fetch("y").to_f - left.fetch("y").to_f) * ratio)
    end

    def tank_x(index, count)
      margin = 100.0
      return WIDTH / 2.0 if count <= 1

      margin + ((WIDTH - (margin * 2)) * index / (count - 1).to_f)
    end

    def tank_for(state, login)
      Array(state["tanks"]).find { |tank| tank.fetch("login") == login }
    end

    def active_players(state)
      Array(state["players"]).select { |player| player.fetch("active", true) }
    end

    def signup_due?(state)
      parse_time(state["signup_ends_at"]) <= clock.call
    end

    def fire_due?(state, _config)
      parse_time(state["next_fire_at"]) <= clock.call
    end

    def round_timeout?(state)
      parse_time(state["round_ends_at"]) <= clock.call
    end

    def ending_due?(state)
      parse_time(state["restore_at"]) <= clock.call
    end

    def parse_time(value)
      value ? Time.iso8601(value.to_s) : Time.at(0).utc
    rescue ArgumentError
      Time.at(0).utc
    end

    def signup_seconds(config)
      positive_integer(config["signup_seconds"], 30)
    end

    def fire_interval_seconds(config)
      positive_integer(config["fire_interval_seconds"], 30)
    end

    def max_round_seconds(config)
      positive_integer(config["max_round_seconds"], 600)
    end

    def positive_integer(value, fallback)
      Integer(value).positive? ? Integer(value) : fallback
    rescue ArgumentError, TypeError
      fallback
    end

    def public_config(config)
      config.slice("trigger_command", "signup_command", "aim_command", "weapon_command", "signup_seconds", "fire_interval_seconds", "max_round_seconds", "scene_name", "web_source_name", "width", "height")
    end

    def player_identity(message)
      { "login" => login_name(message), "display_name" => display_name(message) }
    end

    def login_name(message)
      message.name.to_s.downcase
    end

    def display_name(message)
      message.display_name.to_s.presence || login_name(message)
    end

    def iso_now
      clock.call.iso8601
    end

    def clamp(value, min, max)
      [ [ value, min ].max, max ].min
    end
  end
end
