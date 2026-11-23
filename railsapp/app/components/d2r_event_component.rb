# frozen_string_literal: true

require "time"

class D2rEventComponent < ApplicationComponent
  with_collection_parameter :event

  def initialize(event:)
    @event = event
  end

  def message
    @event.fetch("message")
  end

  def timestamp
    Time.iso8601(@event.fetch("at")).strftime("%H:%M:%S")
  rescue ArgumentError
    @event.fetch("at").to_s
  end

  def tone_class
    case @event.fetch("type")
    when "d2r.player.died" then "border-red-400/70 text-red-100"
    when "d2r.boss.slain" then "border-amber-300/70 text-amber-100"
    when "d2r.loading.started", "d2r.loading.finished" then "border-slate-500/70 text-slate-200"
    else "border-cyan-400/70 text-white"
    end
  end
end
