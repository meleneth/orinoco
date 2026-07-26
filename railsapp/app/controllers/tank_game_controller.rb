# frozen_string_literal: true

class TankGameController < ApplicationController
  layout "overlay"
  skip_before_action :ensure_obs_config!

  def overlay
    render TankGameOverlayComponent.new(state: state_store.read)
  end

  def state
    render json: state_store.read
  end

  private

  def state_store
    @state_store ||= TankGame::StateStore.new(redis: redis)
  end

  def redis
    @redis ||= Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
  end
end
