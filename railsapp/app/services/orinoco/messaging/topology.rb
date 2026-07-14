# frozen_string_literal: true

require 'debug'
require 'uri'

module Orinoco
  module Messaging
    class Topology
      VISIBILITY_TIMEOUT = "VisibilityTimeout"
      RECEIVE_MESSAGE_WAIT_TIME_SECONDS = "ReceiveMessageWaitTimeSeconds"
      REDRIVE_POLICY = "RedrivePolicy"
      QUEUE_ARN = "QueueArn"
      ALL_ATTRIBUTES = "All"

      TopicSpec = Data.define(:name, :queues)
      QueueSpec = Data.define(:name, :attributes)

      TopicRef = Data.define(:name, :arn)
      QueueRef = Data.define(:name, :url, :arn)

      def self.define(sns_client:, sqs_client:, logger: Rails.logger, &block)
        builder = Builder.new(
          sns_client:,
          sqs_client:,
          logger:
        )
        builder.instance_eval(&block)
        builder.topology
      end

      attr_reader :topics

      def initialize(sns_client:, sqs_client:, logger:, topics:)
        @sns_client = sns_client
        @sqs_client = sqs_client
        @logger = logger
        @topics = topics

        @topic_refs_by_name = {}
        @queue_refs_by_name = {}
      end

      def ensure!
        topics.each do |topic_spec|
          topic_ref = ensure_topic!(topic_spec)
          @topic_refs_by_name[topic_ref.name] = topic_ref

          topic_spec.queues.each do |queue_spec|
            queue_ref = ensure_queue!(queue_spec)
            @queue_refs_by_name[queue_ref.name] = queue_ref

            ensure_subscription!(
              topic_arn: topic_ref.arn,
              queue_arn: queue_ref.arn
            )
          end
        end

        self
      end

      def topic_arn(name)
        @topic_refs_by_name.fetch(name).arn
      end

      def queue_url(name)
        @queue_refs_by_name.fetch(name).url
      end

      def queue_arn(name)
        @queue_refs_by_name.fetch(name).arn
      end

      def topic_ref(name)
        @topic_refs_by_name.fetch(name)
      end

      def queue_ref(name)
        @queue_refs_by_name.fetch(name)
      end

      def queue_refs
        @queue_refs_by_name.values.sort_by(&:name)
      end

      private

      attr_reader :sns_client, :sqs_client, :logger

      def normalize_queue_url(raw_url)
        returned_uri = URI.parse(raw_url)
        base_uri = URI.parse(ENV.fetch("EVENT_PIPELINE_GOAWS_URL"))

        normalized_uri = base_uri.dup
        normalized_uri.path = returned_uri.path
        normalized_uri.query = returned_uri.query
        normalized_uri.fragment = returned_uri.fragment

        normalized_uri.to_s
      end

      def ensure_topic!(topic_spec)
        arn = sns_client.create_topic(name: topic_spec.name).topic_arn
        logger.info("Ensured SNS topic #{topic_spec.name} => #{arn}")
        TopicRef.new(name: topic_spec.name, arn: arn)
      end

      def ensure_queue!(queue_spec)
        url = sqs_client.create_queue(
          queue_name: queue_spec.name,
          attributes: translate_queue_attributes(queue_spec.attributes)
        ).queue_url

        url = normalize_queue_url(url)

        arn = sqs_client.get_queue_attributes(
          queue_url: url,
          attribute_names: [ALL_ATTRIBUTES]
        ).attributes.fetch(QUEUE_ARN)

        logger.info("Ensured SQS queue #{queue_spec.name} => #{url} (#{arn})")
        QueueRef.new(name: queue_spec.name, url: url, arn: arn)
      end

      def ensure_subscription!(topic_arn:, queue_arn:)
        subscriptions = []
        next_token = nil

        loop do
          response = sns_client.list_subscriptions_by_topic(
            topic_arn:,
            next_token:
          )

          subscriptions.concat(response.subscriptions)
          next_token = response.next_token
          break if next_token.blank?
        end

        return if subscriptions.any? { |sub| sub.protocol == "sqs" && sub.endpoint == queue_arn }

        sns_client.subscribe(
          topic_arn:,
          protocol: "sqs",
          endpoint: queue_arn
        )

        logger.info("Ensured SNS subscription #{topic_arn} -> #{queue_arn}")
      end

      def translate_queue_attributes(attributes)
        {}.tap do |translated|
          translated[VISIBILITY_TIMEOUT] = attributes[:visibility_timeout].to_s if attributes.key?(:visibility_timeout)
          translated[RECEIVE_MESSAGE_WAIT_TIME_SECONDS] = attributes[:receive_message_wait_time_seconds].to_s if attributes.key?(:receive_message_wait_time_seconds)
          translated[REDRIVE_POLICY] = attributes[:redrive_policy].to_json if attributes.key?(:redrive_policy)
        end
      end

      class Builder
        attr_reader :topology

        def initialize(sns_client:, sqs_client:, logger:)
          @topics = []
          @topology = Topology.new(
            sns_client:,
            sqs_client:,
            logger:,
            topics: @topics
          )
        end

        def topic(name, &block)
          builder = TopicBuilder.new(name)
          builder.instance_eval(&block) if block

          @topics << TopicSpec.new(name:, queues: builder.queues)
        end
      end

      class TopicBuilder
        attr_reader :queues

        def initialize(name)
          @name = name
          @queues = []
        end

        def queue(name, **attributes)
          @queues << QueueSpec.new(name:, attributes:)
        end
      end
    end
  end
end
