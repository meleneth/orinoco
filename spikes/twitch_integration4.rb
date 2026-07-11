#TODO: delete this? what is this being used for?
# frozen_string_literal: true
require 'faye/websocket'
require 'eventmachine'
# require 'json'


channelName        = 'quantumapprentice'
TwitchWebSocketUrl = 'wss://irc-ws.chat.twitch.tv:443'


module TwitchIRC
  Message = Struct.new(
    :tags,
    :prefix,
    :command,
    :params,
    :text,
    keyword_init: true
  ) do
    def nick
      return nil unless prefix

      prefix.split("!", 2).first
    end

    def user
      return nil unless prefix&.include?("!")

      prefix.split("!", 2).last.split("@", 2).first
    end

    def host
      return nil unless prefix&.include?("@")

      prefix.split("@", 2).last
    end

    def channel
      params.first
    end

    def txt
      text
    end
  end

  module_function

  def parse(line)
    rest = line.chomp
    tags = {}
    prefix = nil

    if rest.start_with?("@")
      raw_tags, rest = rest.split(" ", 2)
      tags = parse_tags(raw_tags[1..])
    end

    if rest.start_with?(":")
      raw_prefix, rest = rest.split(" ", 2)
      prefix = raw_prefix[1..]
    end

    command, rest = rest.split(" ", 2)

    params = []
    text = nil

    while rest && !rest.empty?
      if rest.start_with?(":")
        text = rest[1..]
        break
      end

      param, new_rest = rest.split(" ", 2)
      params << param
      #QTODO: I think this is what clears the html
      #      out of the message?
      #      need to add more filter parsing here?
      rest = new_rest.to_s.sub(/\A +/, "")
    end

    Message.new(
      tags: tags,
      prefix: prefix,
      command: command,
      params: params,
      text: text
    )
  end

  def parse_tags(raw_tags)
    raw_tags.split(";").each_with_object({}) do |pair, out|
      key, value = pair.split("=", 2)
      out[key] = unescape_tag_value(value)
    end
  end

  def unescape_tag_value(value)
    return true if value.nil?

    value
      .gsub("\\s", " ")
      .gsub("\\:", ";")
      .gsub("\\r", "\r")
      .gsub("\\n", "\n")
      .gsub("\\\\", "\\")
  end
end



EM.run do
  ws = Faye::WebSocket::Client.new(TwitchWebSocketUrl)

  ws.on :open do |e|
    puts "opening socket"
    ws.send("NICK justinfan69420")
    ws.send("JOIN ##{channelName}")
  end

  ws.on :message do |e|
    data = e.data

    #QTODO: add a PONG response to PING
    puts "Received: #{data}"
    index = data.index(":")
    if data.start_with?("PING")
      substr = data[index]
      ws.send("PONG #{substr}")
      puts "PONG"
    else
      msg = TwitchIRC.parse(data)
      puts(msg)
    end




  end
end
