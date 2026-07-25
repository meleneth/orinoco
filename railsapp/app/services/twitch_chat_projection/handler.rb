# frozen_string_literal: true

require "json"
require "timeout"
require_relative "../wos/chat_guess_tracker"

module TwitchChatProjection
  class Handler
    HISTORY_KEY = "twitch:chat:history"
    HISTORY_LIMIT = 250
    BROADCAST_TIMEOUT_SECONDS = 5

    def initialize(redis:, broadcaster: Turbo::StreamsChannel, wos_guess_tracker: Wos::ChatGuessTracker.new(redis: redis), logger: Rails.logger, broadcast_timeout_seconds: BROADCAST_TIMEOUT_SECONDS)
      @redis = redis
      @broadcaster = broadcaster
      @wos_guess_tracker = wos_guess_tracker
      @logger = logger
      @broadcast_timeout_seconds = broadcast_timeout_seconds
    end

    def call(event)
      message = TwitchChatBridge::Message.from_json(JSON.generate(event.payload))

      persist_message(message)
      track_wos_guess(message)
      broadcast_message(message)
    end

    private

    def persist_message(message)
      @redis.multi do |tx|
        tx.rpush(HISTORY_KEY, message.to_json)
        tx.ltrim(HISTORY_KEY, -HISTORY_LIMIT, -1)
      end
    end

    def track_wos_guess(message)
      @wos_guess_tracker.call(message)
    end

    def broadcast_message(message)
      Timeout.timeout(@broadcast_timeout_seconds) do
        Rails.application.reloader.wrap do
          @broadcaster.broadcast_append_to(
            :chat,
            target: "chat_feed",
            layout: false,
            renderable: ChatMessageComponent.new(message: message)
          )
        end
      end
    rescue StandardError => e
      @logger.warn("[twitch-chat-projection] broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
