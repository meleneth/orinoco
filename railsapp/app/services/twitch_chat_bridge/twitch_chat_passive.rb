# frozen_string_literal: true

# this is the publisher
require "faye/websocket"
require "eventmachine"
# require 'twitchrb'
require "net/http"
require "uri"
require "securerandom"

# $channelName        = 'quantumapprentice'
$channelName        = TwitchConfig.first.channel_name
# $botName            = "justinfan69420"
$botName            = "justinfan#{SecureRandom.random_number(1_000_000)}"
$TwitchWebSocketUrl = "wss://irc-ws.chat.twitch.tv:443"
$_7TV_WebSocketUrl  = "wss://events.7tv.io/v3" # "https://7tv.io/v3/" # emote-sets/global   # users/twitch/#{channelName}"
$stdout.sync        = true
$stderr.sync        = true



def app_config
  @app_config ||= Rails.configuration.x
end

def topology
  @topology ||= app_config.orinoco.messaging_topology
end

def sns
  @sns ||= Aws::SNS::Client.new(**app_config.event_pipeline.aws_client_options)
end

EM.run do
  puts("are we walkin here?")

  Tws = Faye::WebSocket::Client.new($TwitchWebSocketUrl)
  Tws.on :open do |e|
    puts "opening Twitch socket"
    Tws.send("CAP REQ :twitch.tv/commands twitch.tv/tags")
    Tws.send("NICK #{$botName}")
    Tws.send("JOIN ##{$channelName}")
  end

  Tws.on :message do |e|
    data = e.data

    index = data.index(":")
    if data.start_with?("PING")
      substr = data[index]
      Tws.send("PONG #{substr}")
      # QTODO: PONG should go to event pipeline as non-message event type
      puts "PONG"
    else
      warn("twitch data: #{data}")
      parser = TwitchChatBridge::IrcMessageParser.new(
        channel_name: $channelName,
        bot_name: $botName
      )

      msg = parser.parse(data)

      if msg != nil then
        warn("#{msg.name}: #{msg.txt}\n")
        sns.publish(
          topic_arn: topology.topic_arn(Orinoco::Messaging::Names::TWITCH_CHAT_MESSAGE_TOPIC),
          message: JSON.generate(msg)
        )
      end
    end

    # #QTODO:
    ## we don't want it to blind render every message,
    ## we want a way to be able to intercept the messages,

    ## filter out stuff we don't want to keep,
    ## then forward it into a good messages queue
    # good_msg, bad_msg = chat_filter(msg)
  end


  def redis
    @redis ||= Redis.new(url: app_config.scoreboard.redis_url)
  end
  def app_config
    Rails.configuration.x
  end

  # 7tv emotes (jesus this is retarded, getting channel emotes shouldn't be this over-loaded)
  def wtf_this_is_retarded(twitch_name)
    get_twitch_id_7tv_url = URI.parse("https://7tv.io/v3/gql")
    req = Net::HTTP::Post.new(get_twitch_id_7tv_url)
    req.body = {
      query: "query GetTwitchID($query: String!) { users(query: $query) { connections { platform username id } } }",
      variables: { query: twitch_name }
    }.to_json

    res = Net::HTTP.start(get_twitch_id_7tv_url.host, get_twitch_id_7tv_url.port, use_ssl: true) do |http|
      http.request(req)
    end

    # puts("7tv this shouldn't be this retarded: #{res.body}")
    fucking_json = JSON.parse(res.body)
    id = fucking_json['data']['users'][0]['connections'][0]['id']

    return id
  end

  def get_twitch_emotes_7tv(twitch_name)
    # twitch_id_url = URI.parse("https://decapi.me/twitch/id/#{twitch_name}")
    # twitch_id = Net::HTTP.get(twitch_id_url).strip
    twitch_id = wtf_this_is_retarded(twitch_name)

    user_uri  = URI.parse("https://7tv.io/v3/users/twitch/#{twitch_id}")
    res = Net::HTTP.get_response(user_uri)
    emotes = JSON.parse(res.body)
    return emotes
  end

  def get_global_emotes_7tv()
    global_uri = URI.parse("https://7tv.io/v3/emote-sets/global")
    res = Net::HTTP.get_response(global_uri)
    gl_emotes = JSON.parse(res.body)
    return gl_emotes
  end

  # puts("7tv http sending request...\n------\n")
  twitch_emotes_7tv = get_twitch_emotes_7tv($channelName)
  global_emotes_7tv = get_global_emotes_7tv()

  # puts("global emotes: #{global_emotes_7tv}")


  r = redis
  twitch_emotes_7tv['emote_set']['emotes'].each do |emote|
    emote_id   = emote['id']
    emote_name = emote['name']
    # puts("7tv name: #{emote_name} id: #{emote_id}")

    r.hset("twitch_emote_7tv", emote_name, emote_id)
  end
  global_emotes_7tv['emotes'].each do |emote|
    emote_id   = emote['id']
    emote_name = emote['name']
    # puts("7tv global name: #{emote_name} id: #{emote_id}")

    r.hset("global_emote_7tv", emote_name, emote_id)
  end


end
