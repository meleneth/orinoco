# frozen_string_literal: true

class OverlayController < ApplicationController
  layout "overlay"
  skip_before_action :ensure_obs_config!

  def show
    render OverlayComponent.new(
      layers: Overlay::LayerRegistry.layers,
      wos_state: wos_state_store.read,
      d2r_state: D2r::RunProjection.new(redis: redis).snapshot
    )
  end

  private

  def wos_state_store
    @wos_state_store ||= Wos::OverlayStateStore.new(redis: redis)
  end

  def redis
    @redis ||= Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
  end
end
