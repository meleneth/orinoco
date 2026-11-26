# frozen_string_literal: true

class StardewController < ApplicationController
  skip_before_action :ensure_obs_config!

  def show
    redis = Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
    @telemetry = Stardew::TelemetryProjection.new(redis: redis).status
    @configured = ENV["STARDEW_TELEMETRY_TOKEN"].present?
  ensure
    redis&.close
  end
end
