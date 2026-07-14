# frozen_string_literal: true

require "faye/websocket"
require "eventmachine"
require "securerandom"

module TwitchChatBridge
  class Runtime
    def initialize(channel_name:, publisher:, bot_name: nil, websocket_url: "wss://irc-ws.chat.twitch.tv:443", parser_class: IrcMessageParser, logger: nil, on_connected: nil, on_disconnected: nil)
      @channel_name = channel_name
      @publisher = publisher
      @bot_name = bot_name || "justinfan#{SecureRandom.random_number(1_000_000)}"
      @websocket_url = websocket_url
      @parser_class = parser_class
      @logger = logger || ->(message) { warn message }
      @on_connected = on_connected
      @on_disconnected = on_disconnected
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @socket = nil
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
      socket = nil

      @mutex.synchronize do
        return unless @running

        @running = false
        thread = @thread
        socket = @socket
      end

      socket&.close
      EM.stop_event_loop if EM.reactor_running?
      thread&.join(2)
    end

    def running?
      @mutex.synchronize { @running }
    end

    private

    def run_loop
      EM.run do
        parser = @parser_class.new(channel_name: @channel_name, bot_name: @bot_name)
        socket = Faye::WebSocket::Client.new(@websocket_url)
        @mutex.synchronize { @socket = socket }

        socket.on :open do |_event|
          @logger.call("[twitch-bridge/runtime] connected to Twitch chat")
          @on_connected&.call
          socket.send("CAP REQ :twitch.tv/commands twitch.tv/tags")
          socket.send("NICK #{@bot_name}")
          socket.send("JOIN ##{@channel_name}")
        end

        socket.on :message do |event|
          handle_socket_message(socket, parser, event.data)
        end

        socket.on :close do |event|
          @logger.call("[twitch-bridge/runtime] socket closed: #{event.code} #{event.reason}")
          @on_disconnected&.call
          @mutex.synchronize do
            @socket = nil
            @running = false
          end
          EM.stop_event_loop if EM.reactor_running?
        end
      end
    ensure
      @mutex.synchronize do
        @socket = nil
        @thread = nil
        @running = false
      end
    end

    def handle_socket_message(socket, parser, data)
      if data.start_with?("PING")
        socket.send("PONG #{data.split(":", 2).last}")
        return
      end

      message = parser.parse(data)
      @publisher.call(message) if message
    rescue StandardError => e
      @logger.call("[twitch-bridge/runtime] message failed: #{e.class}: #{e.message}")
    end
  end
end