# frozen_string_literal: true

require "rails_helper"
require "json"
require "support/fake_sqs_client"

RSpec.describe WosBrainProjectionWorker do
  class WosBrainProjectionWorkerSpecRedis
    attr_reader :values

    def initialize
      @values = {}
    end

    def set(key, value)
      @values[key] = value
    end

    def get(key)
      @values[key]
    end
  end

  let(:message) { double(body: event_body, receipt_handle: "rh-1") }
  let(:sqs) { FakeSqsClient.new(receive_batches: [[message]]) }
  let(:redis) { WosBrainProjectionWorkerSpecRedis.new }
  let(:topology) do
    Class.new do
      def queue_url(name)
        "http://goaws:31040/000000000000/#{name}"
      end

      def topic_arn(name)
        "arn:aws:sns:us-east-1:000000000000:#{name}"
      end
    end.new
  end

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(Aws::SQS::Client).to receive(:new).and_return(sqs)
    allow(Aws::SNS::Client).to receive(:new).and_return(double("sns"))
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

    Rails.application.config.x.orinoco.messaging_topology = topology
    Rails.application.config.x.event_pipeline.aws_client_options = {
      endpoint: "http://goaws:4100",
      region: "us-east-1",
      access_key_id: "fake",
      secret_access_key: "fake"
    }
    Rails.application.config.x.scoreboard.redis_url = "redis://localhost:6379/0"
  end

  it "projects recognized WOS board events into Redis and deletes the message" do
    described_class.new.run_once

    projected = JSON.parse(redis.values.fetch(Wos::OverlayStateStore::KEY))
    expect(projected.dig("recognition", "letters").map { |tile| tile["char"] }.join).to eq("WOS")
    expect(sqs.delete_calls).to eq([
      {
        queue_url: "http://goaws:31040/000000000000/#{Orinoco::Messaging::Names::WOS_BOARD_RECOGNIZED_QUEUE}",
        receipt_handle: "rh-1"
      }
    ])
    expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to)
  end

  def event_body
    JSON.generate(
      "type" => "wos.board.recognized",
      "source" => "spec",
      "occurred_at" => "2026-07-13T08:00:00Z",
      "payload" => {
        "recognition" => {
          "ruleset" => { "mode" => "base", "hidden_letters" => 0, "fake_letters" => 0 },
          "letters" => [ { "char" => "W" }, { "char" => "O" }, { "char" => "S" } ]
        }
      },
      "correlation" => {}
    )
  end
end