# frozen_string_literal: true

class D2rRunsController < ApplicationController
  skip_before_action :ensure_obs_config!

  def show
    render json: D2r::RunProjection.new(redis: redis).snapshot
  end

  private

  def redis
    @redis ||= Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
  end
end
