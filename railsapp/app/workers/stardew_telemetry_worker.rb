# frozen_string_literal: true
require_relative "../services/orinoco/pipeline"

class StardewTelemetryWorker
  def run
    config = Rails.configuration.x
    projection = Stardew::TelemetryProjection.new(redis: Redis.new(url: config.scoreboard.redis_url))
    definition = Orinoco::Pipeline.processor(:stardew_telemetry) do
      consume Orinoco::Messaging::Names::STARDEW_EVENTS_QUEUE, wait_time_seconds: 1
      on("stardew.snapshot") do |event, _context|
        next unless projection.call(event)

        begin
          Rails.application.reloader.wrap do
            Turbo::StreamsChannel.broadcast_replace_to(
              "stardew_telemetry",
              target: "stardew_live_telemetry",
              partial: "stardew/telemetry",
              locals: { telemetry: projection.status, configured: ENV["STARDEW_TELEMETRY_TOKEN"].present? }
            )
          end
        rescue StandardError => e
          Rails.logger.warn("[stardew] dashboard broadcast failed: #{e.class}: #{e.message}")
        end
      end
    end
    Orinoco::Pipeline::Runner.new(
      definition: definition,
      sqs: Aws::SQS::Client.new(**config.event_pipeline.aws_client_options),
      sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
      topology: config.orinoco.messaging_topology
    ).run
  end
end
