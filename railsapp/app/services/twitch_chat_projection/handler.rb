# frozen_string_literal: true

require "json"

module TwitchChatProjection
  class Handler
    HISTORY_KEY = "twitch:chat:history"
    HISTORY_LIMIT = 250

    def initialize(redis:, broadcaster: Turbo::StreamsChannel)
      @redis = redis
      @broadcaster = broadcaster
    end

    def call(event)
      message = TwitchChatBridge::Message.from_json(JSON.generate(event.payload))

      persist_message(message)
      broadcast_message(message)
    end

    private

    def persist_message(message)
      @redis.multi do |tx|
        tx.rpush(HISTORY_KEY, message.to_json)
        tx.ltrim(HISTORY_KEY, -HISTORY_LIMIT, -1)
      end
    end

    def broadcast_message(message)
      Rails.application.reloader.wrap do
        @broadcaster.broadcast_append_to(
          :chat,
          target: "chat_feed",
          layout: false,
          renderable: ChatMessageComponent.new(message: message)
        )
      end
    end
  end
end