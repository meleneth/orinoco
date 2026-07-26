# frozen_string_literal: true

require "rails_helper"

RSpec.describe TankGame::TickScheduler do
  class TankGameTickSchedulerSpecSqs
    attr_reader :messages

    def initialize
      @messages = []
    end

    def send_message(args)
      messages << args
    end
  end

  let(:now) { Time.utc(2026, 7, 25, 20, 0, 0) }
  let(:sqs) { TankGameTickSchedulerSpecSqs.new }
  let(:topology) { instance_double("topology", queue_url: "http://goaws/queue/tank-game-tick") }

  it "sends a delayed pipeline tick event directly to SQS" do
    scheduler = described_class.new(sqs: sqs, topology: topology, clock: -> { now })

    scheduler.schedule!(
      { "round_id" => "round-1", "phase" => "active" },
      run_at: now + 30,
      reason: "combat_tick"
    )

    expect(sqs.messages.length).to eq(1)
    message = sqs.messages.first
    expect(message).to include(
      queue_url: "http://goaws/queue/tank-game-tick",
      delay_seconds: 30
    )
    body = JSON.parse(message.fetch(:message_body))
    expect(body).to include(
      "type" => "tank_game.tick",
      "source" => "tank_game",
      "correlation" => { "round_id" => "round-1" }
    )
    expect(body.fetch("payload")).to include(
      "round_id" => "round-1",
      "phase" => "active",
      "reason" => "combat_tick",
      "run_at" => (now + 30).iso8601
    )
  end
end
