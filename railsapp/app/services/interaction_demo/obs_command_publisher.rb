# frozen_string_literal: true

require "json"
require_relative "../orinoco/pipeline"

module InteractionDemo
  class ObsCommandPublisher
    def initialize(sns:, topology:)
      @sns = sns
      @topology = topology
    end

    def publish!(request)
      @sns.publish(
        topic_arn: @topology.topic_arn(Orinoco::Messaging::Names::OBS_COMMAND_TOPIC),
        message: JSON.generate(
          Orinoco::Pipeline::Event.build(
            "obs.command.requested",
            { "request" => request },
            source: "interaction_demo"
          ).to_h
        )
      )

      request
    end
  end
end