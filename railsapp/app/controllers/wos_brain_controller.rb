# frozen_string_literal: true

class WosBrainController < ApplicationController
  skip_before_action :ensure_obs_config!

  def show
    @config = AffordanceConfig.fetch!(:wos_brain)
    @status = status_store.read
    @overlay_state = overlay_state_store.read
  end

  private

  def status_store
    @status_store ||= Wos::StatusStore.new(redis: redis)
  end

  def overlay_state_store
    @overlay_state_store ||= Wos::OverlayStateStore.new(redis: redis)
  end

  def redis
    @redis ||= Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
  end
end