# frozen_string_literal: true

class TankGameOverlayComponent < ApplicationComponent
  WIDTH = 1920
  HEIGHT = 1080

  def initialize(state:)
    @state = state || {}
  end

  private

  attr_reader :state

  def phase
    state.fetch("phase", "idle")
  end

  def players
    Array(state["players"])
  end

  def tanks
    Array(state["tanks"])
  end

  def terrain
    Array(state["terrain"])
  end

  def projectiles
    Array(state["projectiles"])
  end

  def explosions
    Array(state["explosions"])
  end

  def status_text
    state.fetch("status", "Waiting for !TankGame").to_s
  end

  def countdown_text
    return nil unless phase == "signup"

    ends_at = Time.iso8601(state.fetch("signup_ends_at"))
    remaining = [ (ends_at - Time.now.utc).ceil, 0 ].max
    "Signup: #{remaining}s"
  rescue ArgumentError, KeyError
    "Signup open"
  end

  def terrain_points
    points = terrain.map { |point| "#{point.fetch("x", 0)},#{point.fetch("y", 900)}" }
    ([ "0,#{HEIGHT}" ] + points + [ "#{WIDTH},#{HEIGHT}" ]).join(" ")
  end

  def player_for(login)
    players.find { |player| player["login"] == login } || {}
  end

  def tank_color(index, active)
    return "#64748b" unless active

    %w[#22c55e #38bdf8 #f97316 #e879f9 #facc15 #a78bfa #fb7185 #2dd4bf][index % 8]
  end

  def barrel_end(tank, player)
    angle = player.fetch("angle", 45).to_f * Math::PI / 180.0
    length = 46
    x = tank.fetch("turret_x", tank.fetch("x", 0)).to_f + (Math.cos(angle) * length)
    y = tank.fetch("turret_y", tank.fetch("y", 0)).to_f - (Math.sin(angle) * length)
    [ x.round(2), y.round(2) ]
  end
end
