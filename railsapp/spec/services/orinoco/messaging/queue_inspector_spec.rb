# frozen_string_literal: true

require "spec_helper"
require "orinoco/messaging/queue_inspector"

RSpec.describe Orinoco::Messaging::QueueInspector do
  let(:queue_ref_class) { Data.define(:name, :url, :arn) }
  let(:queue_ref) { queue_ref_class.new(name: "queue.one", url: "queue-url", arn: "queue-arn") }
  let(:topology) do
    Class.new do
      def initialize(queue_ref)
        @queue_ref = queue_ref
      end

      def queue_refs
        [@queue_ref]
      end

      def queue_ref(name)
        raise KeyError, name unless name == @queue_ref.name

        @queue_ref
      end
    end.new(queue_ref)
  end
  let(:sqs) do
    Class.new do
      attr_reader :receive_calls, :purge_calls

      def initialize
        @receive_calls = []
        @purge_calls = []
      end

      def get_queue_attributes(**)
        Struct.new(:attributes).new(
          {
            "ApproximateNumberOfMessages" => "3",
            "ApproximateNumberOfMessagesNotVisible" => "2",
            "ApproximateNumberOfMessagesDelayed" => "1"
          }
        )
      end

      def purge_queue(**kwargs)
        @purge_calls << kwargs
      end

      def receive_message(**kwargs)
        @receive_calls << kwargs
        Struct.new(:messages).new(
          [
            Struct.new(:message_id, :body, :attributes).new(
              "m-1",
              JSON.generate("type" => "example.event", "payload" => {}),
              { "ApproximateReceiveCount" => "1" }
            )
          ]
        )
      end
    end.new
  end

  subject(:inspector) { described_class.new(sqs: sqs, topology: topology) }

  it "lists queue counts" do
    queue = inspector.queues.first

    expect(queue.name).to eq("queue.one")
    expect(queue.visible).to eq(3)
    expect(queue.in_flight).to eq(2)
    expect(queue.delayed).to eq(1)
  end

  it "clears a queue by purging its resolved queue URL" do
    inspector.clear("queue.one")

    expect(sqs.purge_calls).to eq([{ queue_url: "queue-url" }])
  end
  it "peeks messages without deleting them" do
    messages = inspector.peek("queue.one")

    expect(messages.first.message_id).to eq("m-1")
    expect(messages.first.parsed_body).to eq("type" => "example.event", "payload" => {})
    expect(sqs.receive_calls.last).to include(
      queue_url: "queue-url",
      visibility_timeout: 0,
      wait_time_seconds: 0
    )
  end
end
