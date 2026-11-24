# frozen_string_literal: true

# Human-facing run archive. The JSON endpoints and the OBS overlay remain
# separate consumers of the same durable, event-derived D2rRun records.
class D2rLogController < ApplicationController
  skip_before_action :ensure_obs_config!

  PAGE_SIZE = 25

  def index
    @kind = params[:kind].to_s.strip
    @page = [params.fetch(:page, 1).to_i, 1].max
    @kinds = D2rRun.where.not(run_kind: [nil, ""]).distinct.order(:run_kind).pluck(:run_kind)
    scope = D2rRun.recent_first
    scope = scope.where(run_kind: @kind) if @kind.present?
    @total = scope.count
    @pages = [(@total.to_f / PAGE_SIZE).ceil, 1].max
    @page = [@page, @pages].min
    @runs = scope.offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
  end

  def show
    @run = D2rRun.find(params[:id])
    @drops = @run.loot_drops.order(observed_at: :asc, id: :asc)
  end
end
