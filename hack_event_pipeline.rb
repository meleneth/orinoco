#!/usr/bin/env ruby

require 'json'
require 'aws-sdk-sns'
require 'aws-sdk-sqs'

ENDPOINT_URL = 'http://localhost:31040'
REGION       = 'us-east-1'

QUEUE_NAME = 'hack-events'
TOPIC_NAME = 'hack-events-topic'

def aws_config
  {
    region: REGION,
    endpoint: ENDPOINT_URL,
    access_key_id: 'fake',
    secret_access_key: 'fake'
  }
end

@sns = Aws::SNS::Client.new(**aws_config)
@sqs = Aws::SQS::Client.new(**aws_config)

def verify!(label)
  puts "\n== #{label} =="
  result = yield
  pp result
  result
rescue StandardError => e
  warn "FAILED: #{e.class}: #{e.message}"
  exit 1
end

# 1. Create the SQS queue
create_queue_resp = verify!("create SQS queue #{QUEUE_NAME}") do
  @sqs.create_queue(queue_name: QUEUE_NAME)
end

require 'uri'

def rewrite_queue_url(queue_url, public_endpoint)
  q = URI(queue_url)
  p = URI(public_endpoint)

  q.scheme = p.scheme
  q.host   = p.host
  q.port   = p.port
  q.to_s
end

queue_url = rewrite_queue_url(create_queue_resp.queue_url, ENDPOINT_URL)

puts "queue_url=#{queue_url}"

# 2. Fetch queue attributes, including the ARN
queue_attrs_resp = verify!('get SQS queue attributes') do
  @sqs.get_queue_attributes(
    queue_url: queue_url,
    attribute_names: ['All']
  )
end

queue_arn = queue_attrs_resp.attributes['QueueArn']
abort('QueueArn missing from queue attributes') unless queue_arn

puts "queue_arn=#{queue_arn}"

# 3. Create the SNS topic
create_topic_resp = verify!("create SNS topic #{TOPIC_NAME}") do
  @sns.create_topic(name: TOPIC_NAME)
end

topic_arn = create_topic_resp.topic_arn
puts "topic_arn=#{topic_arn}"

# 4. Subscribe the SQS queue to the SNS topic
#
# In real AWS you'd usually also set an SQS policy allowing the SNS topic
# to publish to the queue. goaws has limited SetQueueAttributes support,
# so for local goaws use, direct subscribe is usually the happy path.

subscribe_resp = verify!('subscribe SQS queue to SNS topic') do
  @sns.subscribe(
    topic_arn: topic_arn,
    protocol: 'sqs',
    endpoint: queue_arn
  )
end

subscription_arn = subscribe_resp.subscription_arn
puts "subscription_arn=#{subscription_arn}"

# Optional: make SQS receive the raw payload instead of SNS envelope JSON
begin
  verify!('set RawMessageDelivery=true on subscription') do
    @sns.set_subscription_attributes(
      subscription_arn: subscription_arn,
      attribute_name: 'RawMessageDelivery',
      attribute_value: 'true'
    )
  end
rescue StandardError => e
  warn "RawMessageDelivery not set: #{e.class}: #{e.message}"
end

# 5. Verify queue exists
verify!('list SQS queues') do
  @sqs.list_queues
end

# 6. Verify topic exists
verify!('list SNS topics') do
  @sns.list_topics
end

# 7. Verify subscription exists for the topic
verify!('list subscriptions by topic') do
  @sns.list_subscriptions_by_topic(topic_arn: topic_arn)
end

# 8. End-to-end smoke test: publish a message and read it from SQS
message_body = {
  event: 'hack.test',
  payload: {
    ok: true,
    generated_by: 'hack_event_pipeline.rb'
  }
}.to_json

verify!('publish test message to SNS topic') do
  @sns.publish(
    topic_arn: topic_arn,
    message: message_body
  )
end

receive_resp = verify!('receive message from SQS queue') do
  @sqs.receive_message(
    queue_url: queue_url,
    max_number_of_messages: 1,
    wait_time_seconds: 1
  )
end

messages = receive_resp.messages || []

if messages.empty?
  warn "\nNo messages received from SQS. The pipe may not be connected."
  exit 2
end

puts "\n== received message body =="
puts messages.first.body
puts "\nPipeline is alive. Tiny packet ghost successfully traversed the tube. ⚙️"
