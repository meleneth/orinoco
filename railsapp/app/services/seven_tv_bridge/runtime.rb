# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module SevenTvBridge
  class Runtime
    DEFAULT_REFRESH_INTERVAL = 15 * 60

    def initialize(
      channel_name:,
      redis:,
      logger: nil,
      on_connected: nil,
      on_disconnected: nil,
      refresh_interval: DEFAULT_REFRESH_INTERVAL,
      sleeper: nil,
      http_getter: nil,
      http_poster: nil
    )
      @channel_name = channel_name
      @redis = redis
      @logger = logger || ->(message) { warn message }
      @on_connected = on_connected
      @on_disconnected = on_disconnected
      @refresh_interval = refresh_interval
      @sleeper = sleeper
      @http_getter = http_getter || method(:default_get_response)
      @http_poster = http_poster || method(:default_post)
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @condition = ConditionVariable.new
    end

    def start!
      @mutex.synchronize do
        return if @running

        @running = true
        @thread = Thread.new { run_loop }
      end
    end

    def stop!
      thread = nil

      @mutex.synchronize do
        return unless @running

        @running = false
        @condition.broadcast
        thread = @thread
      end

      thread&.join(2)
      @on_disconnected&.call
    end

    def running?
      @mutex.synchronize { @running }
    end

    def refresh!
      sync_once
    end

    private

    def run_loop
      @on_connected&.call

      while running?
        sync_once
        wait_for_next_refresh
      end
    rescue StandardError => e
      @logger.call("[7tv-bridge/runtime] sync failed: #{e.class}: #{e.message}")
      @on_disconnected&.call(error: "runtime loop failed: #{e.class}: #{e.message}")
    ensure
      @mutex.synchronize do
        @running = false
        @thread = nil
      end
    end

    def wait_for_next_refresh
      if @sleeper
        @sleeper.call(@refresh_interval)
        return
      end

      @mutex.synchronize do
        @condition.wait(@mutex, @refresh_interval) if @running
      end
    end

    # 7tv emotes (jesus this is still more overloaded than it should be)
    def wtf_this_is_retarded(twitch_name)
      get_twitch_id_7tv_url = URI.parse("https://7tv.io/v3/gql")
      req_body = {
        query: "query GetTwitchID($query: String!) { users(query: $query) { connections { platform username id } } }",
        variables: { query: twitch_name }
      }.to_json

      res = @http_poster.call(get_twitch_id_7tv_url, req_body)
      fucking_json = JSON.parse(res.body)
      fucking_json.fetch("data").fetch("users").first.fetch("connections").first.fetch("id")
    end

    def get_twitch_emotes_7tv(twitch_name)
      twitch_id = wtf_this_is_retarded(twitch_name)

      user_uri = URI.parse("https://7tv.io/v3/users/twitch/#{twitch_id}")
      res = @http_getter.call(user_uri)
      JSON.parse(res.body)
    end

    def get_global_emotes_7tv
      global_uri = URI.parse("https://7tv.io/v3/emote-sets/global")
      res = @http_getter.call(global_uri)
      JSON.parse(res.body)
    end

    def sync_once
      @logger.call("[7tv-bridge/runtime] refreshing 7TV emotes for #{@channel_name}")

      twitch_emotes_7tv = get_twitch_emotes_7tv(@channel_name)
      global_emotes_7tv = get_global_emotes_7tv

      twitch_count = write_emote_hash("twitch_emote_7tv", twitch_emotes_7tv.fetch("emote_set").fetch("emotes"))
      global_count = write_emote_hash("global_emote_7tv", global_emotes_7tv.fetch("emotes"))

      @logger.call("[7tv-bridge/runtime] refreshed #{twitch_count} channel and #{global_count} global emotes")
    end

    def write_emote_hash(key, emotes)
      @redis.del(key) if @redis.respond_to?(:del)

      emotes.each do |emote|
        emote_id = emote.fetch("id")
        emote_name = emote.fetch("name")
        @redis.hset(key, emote_name, emote_id)
      end

      emotes.length
    end

    def default_get_response(uri)
      Net::HTTP.get_response(uri)
    end

    def default_post(uri, body)
      req = Net::HTTP::Post.new(uri)
      req.body = body
      req["Content-Type"] = "application/json"

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(req)
      end
    end
  end
end
