# frozen_string_literal: true

require_relative "../services/d2r/run_archive"
require_relative "../services/d2r/run_projection_handler"
require_relative "../services/orinoco/pipeline"

class D2rRunProjectionWorker
  def run
    runner.run
  end

  def run_once
    runner.run_once
  end

  private

  def runner
    @runner ||= Orinoco::Pipeline::Runner.new(
      definition: definition,
      sqs: Aws::SQS::Client.new(**config.event_pipeline.aws_client_options),
      sns: Aws::SNS::Client.new(**config.event_pipeline.aws_client_options),
      topology: config.orinoco.messaging_topology
    )
  end

  def definition
    handler = D2r::RunProjectionHandler.new(
      projection: D2r::RunProjection.new(redis: Redis.new(url: config.scoreboard.redis_url))
    )
    @definition ||= Orinoco::Pipeline.processor(:d2r_run_projection) do
      consume Orinoco::Messaging::Names::D2R_EVENTS_QUEUE, wait_time_seconds: 1
      %w[d2r.state.changed d2r.area.banner.visible d2r.boss.engaged d2r.boss.slain
         d2r.player.died d2r.loading.started d2r.loading.finished d2r.game.started
         d2r.game.ended d2r.run.selected d2r.run.step d2r.level.changed
         d2r.area.changed d2r.difficulty.changed d2r.terror_zones.changed
         d2r.character.selection.visible
         d2r.character.creation.visible].each do |type|
        on(type) { |event, _context| handler.call(event) }
      end
    end
  end

  def config
    Rails.configuration.x
  end
end
