# frozen_string_literal: true

require_relative "../services/orinoco/pipeline"
require_relative "../services/tank_game/handler"
require_relative "../services/tank_game/tick_scheduler"
require_relative "../services/overlay/toast_broadcaster"

class TankGameProcessorWorker
  def initialize(wait_time_seconds: 1, max_number_of_messages: 10, sleeper: ->(seconds) { sleep seconds })
    @wait_time_seconds = wait_time_seconds
    @max_number_of_messages = max_number_of_messages
    @sleeper = sleeper
    @stop_requested = false
  end

  def run
    install_signal_handlers
    loop do
      break if @stop_requested

      run_once
      @sleeper.call(0.25)
    end
  end

  def run_once
    process_queue(Orinoco::Messaging::Names::TANK_GAME_TWITCH_QUEUE) { |event| handler.handle_chat_event(event) }
    process_queue(Orinoco::Messaging::Names::TANK_GAME_OBS_RESULT_QUEUE) { |event| handler.handle_obs_result(event) }
    process_queue(Orinoco::Messaging::Names::TANK_GAME_TICK_QUEUE) { |event| handler.handle_tick_event(event) }
  end

  private

  def process_queue(queue_name)
    queue_url = topology.queue_url(queue_name)
    response = sqs.receive_message(
      queue_url: queue_url,
      wait_time_seconds: @wait_time_seconds,
      max_number_of_messages: @max_number_of_messages
    )

    Array(response.messages).each do |message|
      event = Orinoco::Pipeline::Event.from_hash(Orinoco::Messaging::AwsMessage.unwrap_body(message.body))
      yield event
      sqs.delete_message(queue_url: queue_url, receipt_handle: message.receipt_handle)
    rescue StandardError => e
      Rails.logger.warn("[tank-game] failed to process #{queue_name}: #{e.class}: #{e.message}")
    end
  end

  def handler
    @handler ||= TankGame::Handler.new(
      redis: redis,
      publisher: publisher,
      inventory_reader: inventory_reader,
      tick_scheduler: tick_scheduler,
      toast_broadcaster: toast_broadcaster
    )
  end

  def toast_broadcaster
    @toast_broadcaster ||= Overlay::ToastBroadcaster.new
  end

  def tick_scheduler
    @tick_scheduler ||= TankGame::TickScheduler.new(
      sqs: sqs,
      topology: topology
    )
  end

  def publisher
    @publisher ||= Orinoco::Pipeline::Publisher.new(
      sns: sns,
      topology: topology,
      default_topic: Orinoco::Messaging::Names::OBS_COMMAND_TOPIC
    )
  end

  def inventory_reader
    @inventory_reader ||= ObsBridge::InventoryReader.new(redis: redis, bridge_id: bridge_id)
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def sns
    @sns ||= Aws::SNS::Client.new(**config.event_pipeline.aws_client_options)
  end

  def redis
    @redis ||= Redis.new(url: config.scoreboard.redis_url)
  end

  def topology
    config.orinoco.messaging_topology
  end

  def bridge_id
    config.obs_bridge.bridge_id || "obs_bridge"
  end

  def config
    Rails.configuration.x
  end

  def install_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) { @stop_requested = true }
    end
  end
end
