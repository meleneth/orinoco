# frozen_string_literal: true

require "spec_helper"
require "orinoco/pipeline"

RSpec.describe Orinoco::Pipeline::SqsConsumer do
  let(:queue_url) { "queue-url" }
  let(:sqs) { instance_double(Aws::SQS::Client) }
  let(:context) { instance_double(Orinoco::Pipeline::Context) }
  let(:logger) { ->(_message) {} }

  before do
    allow(sqs).to receive(:receive_message).and_return(double(messages: messages))
    allow(sqs).to receive(:delete_message)
  end

  def message(body, receipt_handle)
    double(body: body, receipt_handle: receipt_handle)
  end

  def event_body(type: "example.event", payload: {})
    JSON.generate(
      "type" => type,
      "source" => "spec",
      "occurred_at" => "2026-07-11T00:00:00Z",
      "payload" => payload,
      "correlation" => {}
    )
  end

  context "when a handler matches and succeeds" do
    let(:messages) { [message(event_body, "rh-1")] }

    it "deletes the message" do
      definition = Orinoco::Pipeline.processor(:spec) do
        on "example.event" do |_event, _ctx|
          true
        end
      end

      described_class.new(
        sqs: sqs,
        queue_url: queue_url,
        definition: definition,
        context: context,
        logger: logger
      ).run_once

      expect(sqs).to have_received(:delete_message).with(queue_url: queue_url, receipt_handle: "rh-1")
    end
  end

  context "when no handler matches" do
    let(:messages) { [message(event_body(type: "example.unknown"), "rh-1")] }

    it "leaves the message undeleted" do
      definition = Orinoco::Pipeline.processor(:spec) do
        on "example.event" do |_event, _ctx|
          true
        end
      end

      described_class.new(
        sqs: sqs,
        queue_url: queue_url,
        definition: definition,
        context: context,
        logger: logger
      ).run_once

      expect(sqs).not_to have_received(:delete_message)
    end
  end

  context "when the handler fails" do
    let(:messages) { [message(event_body, "rh-1")] }

    it "leaves the message undeleted" do
      definition = Orinoco::Pipeline.processor(:spec) do
        on "example.event" do |_event, _ctx|
          raise "boom"
        end
      end

      described_class.new(
        sqs: sqs,
        queue_url: queue_url,
        definition: definition,
        context: context,
        logger: logger
      ).run_once

      expect(sqs).not_to have_received(:delete_message)
    end
  end
end