class ChatController < ApplicationController
  def index
    @messages = redis.lrange("twitch:chat:history", 0, -1)
    @messages = @messages.map do |raw|
      TwitchChatBridge::Message.from_json(raw)
    end
  end

  def redis
    app_config = Rails.configuration.x
    @redis ||= Redis.new(url: app_config.scoreboard.redis_url)
  end
end