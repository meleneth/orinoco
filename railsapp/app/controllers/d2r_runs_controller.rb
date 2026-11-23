# frozen_string_literal: true

class D2rRunsController < ApplicationController
  skip_before_action :ensure_obs_config!

  def index
    limit = params.fetch(:limit, 20).to_i.clamp(1, 100)
    page = params.fetch(:page, 1).to_i.clamp(1, 10_000)
    runs = D2rRun.recent_first
    runs = runs.where(run_kind: params[:kind]) if params[:kind].present?
    render json: {
      page: page, limit: limit, total: runs.count,
      runs: runs.offset((page - 1) * limit).limit(limit).map(&:as_history_json)
    }
  end

  def history
    render json: D2rRun.find(params[:id]).as_history_json
  end

  def show
    render json: D2r::RunProjection.new(redis: redis).snapshot
  end

  private

  def redis
    @redis ||= Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
  end
end
