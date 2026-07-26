# frozen_string_literal: true

require "spec_helper"
require "aws-sdk-sqs"
require "obs_bridge/command_consumer"

RSpec.describe ObsBridge::CommandConsumer do
  let(:queue_url) { "queue-url" }
  let(:signal_queue) { Queue.new }
  let(:sqs) { instance_double(Aws::SQS::Client) }
  let(:logger) { ->(_message) { } }

  before do
    allow(sqs).to receive(:receive_message).and_return(double(messages: [ message ]))
    allow(sqs).to receive(:delete_message)
  end

  subject(:consumer) do
    described_class.new(
      sqs: sqs,
      queue_url: queue_url,
      signal_queue: signal_queue,
      logger: logger
    )
  end

  def run_once(dispatch: nil)
    calls = 0
    consumer.run(stop: -> { calls += 1; calls > 1 }, dispatch: dispatch)
  end

  def command_message(body, receipt_handle)
    double(body: body, receipt_handle: receipt_handle)
  end

  context "with an enveloped OBS command" do
    let(:body) do
      JSON.generate(
        "type" => "obs.command.requested",
        "source" => "spec",
        "occurred_at" => "2026-07-11T00:00:00Z",
        "payload" => {
          "request" => {
            "requestType" => "GetSourceScreenshot",
            "requestData" => { "imageFormat" => "png" }
          },
          "reply_topic" => "orinoco.obs.screenshot.results",
          "correlation" => { "local" => "value" }
        },
        "correlation" => { "request_id" => "req-1" }
      )
    end
    let(:message) { command_message(body, "rh-1") }

    it "preserves request, reply topic, and correlation metadata" do
      run_once

      command = signal_queue.pop(true)
      expect(command).to eq(
        "request" => {
          "requestType" => "GetSourceScreenshot",
          "requestData" => { "imageFormat" => "png" }
        },
        "reply_topic" => "orinoco.obs.screenshot.results",
        "correlation" => {
          "request_id" => "req-1",
          "local" => "value"
        }
      )
      expect(sqs).to have_received(:delete_message).with(queue_url: queue_url, receipt_handle: "rh-1")
    end

    it "leaves the message on the queue when runtime dispatch rejects it" do
      run_once(dispatch: ->(_command) { false })

      expect(signal_queue).to be_empty
      expect(sqs).not_to have_received(:delete_message)
    end
  end

  context "with a legacy raw OBS request" do
    let(:body) do
      JSON.generate(
        "requestType" => "SetSceneItemEnabled",
        "requestData" => { "sceneName" => "Clips" }
      )
    end
    let(:message) { command_message(body, "rh-1") }

    it "still enqueues the raw request" do
      run_once

      expect(signal_queue.pop(true)).to eq(
        "requestType" => "SetSceneItemEnabled",
        "requestData" => { "sceneName" => "Clips" }
      )
    end
  end
end
