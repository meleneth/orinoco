# frozen_string_literal: true
require_relative "../services/orinoco/pipeline"

class StardewTelemetryController < ActionController::API
  before_action :authenticate

  def create
    data = Stardew::Telemetry.parse(request.raw_post)
    config = Rails.configuration.x
    publisher = Orinoco::Pipeline::Publisher.new(
      sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
      topology: config.orinoco.messaging_topology
    )
    publisher.publish("stardew.snapshot", data, topic: Orinoco::Messaging::Names::STARDEW_EVENTS_TOPIC, source: "stardew.smapi")
    head :accepted
  rescue Stardew::Telemetry::Invalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Aws::SNS::Errors::ServiceError => e
    Rails.logger.warn("[stardew] publish failed: #{e.class}")
    head :service_unavailable
  end

  def show
    redis = Redis.new(url: Rails.configuration.x.scoreboard.redis_url)
    render json: Stardew::TelemetryProjection.new(redis: redis).status
  ensure
    redis&.close
  end

  private

  def authenticate
    expected = ENV.fetch("STARDEW_TELEMETRY_TOKEN", "")
    header = request.headers["Authorization"].to_s
    return if expected.present? && header.start_with?("Bearer ") &&
      ActiveSupport::SecurityUtils.secure_compare(expected, header.delete_prefix("Bearer "))

    head :unauthorized
  end
end
