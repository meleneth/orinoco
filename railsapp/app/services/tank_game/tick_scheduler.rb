# frozen_string_literal: true

require "json"

module TankGame
  class TickScheduler
    MAX_SQS_DELAY_SECONDS = 900

    def initialize(sqs:, topology:, queue_name: Orinoco::Messaging::Names::TANK_GAME_TICK_QUEUE, clock: -> { Time.now.utc })
      @sqs = sqs
      @topology = topology
      @queue_name = queue_name
      @clock = clock
    end

    def schedule!(state, run_at:, reason:)
      round_id = state["round_id"].to_s
      return if round_id.empty?

      event = Orinoco::Pipeline::Event.build(
        "tank_game.tick",
        {
          "round_id" => round_id,
          "phase" => state["phase"],
          "reason" => reason,
          "run_at" => run_at.iso8601
        },
        source: "tank_game",
        correlation: { "round_id" => round_id }
      )

      queue_url = topology.queue_url(queue_name)
      delay = delay_seconds(run_at)
      Rails.logger.info("[tank-game] scheduling tick reason=#{reason} round_id=#{round_id} run_at=#{run_at.iso8601} delay_seconds=#{delay} queue=#{queue_name}")
      sqs.send_message(
        queue_url: queue_url,
        message_body: JSON.generate(event.to_h),
        delay_seconds: delay
      )
    end

    private

    attr_reader :sqs, :topology, :queue_name, :clock

    def delay_seconds(run_at)
      [ [ (run_at - clock.call).ceil, 0 ].max, MAX_SQS_DELAY_SECONDS ].min
    end
  end
end
