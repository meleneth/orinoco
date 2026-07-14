# frozen_string_literal: true

require "json"

module Orinoco
  module Pipeline
    class Publisher
      def initialize(sns:, topology:, default_topic: nil, clock: -> { Time.now.utc })
        @sns = sns
        @topology = topology
        @default_topic = default_topic
        @clock = clock
      end

      def publish(type, payload = {}, topic: nil, source: nil, correlation: {})
        topic_name = topic || @default_topic
        raise ArgumentError, "publish topic required" if topic_name.nil?

        event = Event.build(
          type,
          payload,
          source: source,
          correlation: correlation,
          occurred_at: @clock.call.iso8601
        )

        @sns.publish(
          topic_arn: @topology.topic_arn(topic_name),
          message: JSON.generate(event.to_h)
        )

        event
      end
    end
  end
end