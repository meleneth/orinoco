# frozen_string_literal: true

require_relative "messaging/aws_message"
require_relative "pipeline/event"
require_relative "pipeline/publisher"
require_relative "pipeline/context"
require_relative "pipeline/definition"
require_relative "pipeline/sqs_consumer"
require_relative "pipeline/runner"

module Orinoco
  module Pipeline
    module_function

    def processor(name, &block)
      definition = Definition.new(name)
      definition.instance_eval(&block) if block_given?
      definition
    end
  end
end