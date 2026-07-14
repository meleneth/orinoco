# frozen_string_literal: true

require "spec_helper"
require "seven_tv_bridge/runtime"

RSpec.describe SevenTvBridge::Runtime do
  class SevenTvRuntimeFakeRedis
    attr_reader :hashes, :deleted_keys

    def initialize
      @hashes = Hash.new { |hash, key| hash[key] = {} }
      @deleted_keys = []
    end

    def hset(key, field, value)
      @hashes[key][field] = value
    end

    def del(key)
      @deleted_keys << key
      @hashes[key] = {}
    end
  end

  let(:redis) { SevenTvRuntimeFakeRedis.new }
  let(:logger) { ->(_message) {} }
  let(:posted_bodies) { [] }
  let(:http_poster) do
    lambda do |_uri, body|
      posted_bodies << body
      double(body: { data: { users: [ { connections: [ { id: "159825609" } ] } ] } }.to_json)
    end
  end
  let(:http_getter) do
    lambda do |uri|
      case uri.to_s
      when "https://7tv.io/v3/users/twitch/159825609"
        double(body: { emote_set: { emotes: [ { id: "channel-id", name: "ChannelWave" } ] } }.to_json)
      when "https://7tv.io/v3/emote-sets/global"
        double(body: { emotes: [ { id: "global-id", name: "GlobalDance" } ] }.to_json)
      else
        raise "unexpected uri #{uri}"
      end
    end
  end

  subject(:runtime) do
    described_class.new(
      channel_name: "quantumapprentice",
      redis: redis,
      logger: logger,
      http_getter: http_getter,
      http_poster: http_poster
    )
  end

  it "keeps the old 7TV discovery flow and populates the Redis emote hashes" do
    runtime.refresh!

    expect(posted_bodies.first).to include("GetTwitchID")
    expect(redis.hashes.fetch("twitch_emote_7tv")).to eq("ChannelWave" => "channel-id")
    expect(redis.hashes.fetch("global_emote_7tv")).to eq("GlobalDance" => "global-id")
    expect(redis.deleted_keys).to include("twitch_emote_7tv", "global_emote_7tv")
  end
end