# frozen_string_literal: true

require "rails_helper"
require "orinoco/pipeline/event"

RSpec.describe TwitchChatProjection::Handler do
  class TwitchChatProjectionHandlerSpecRedis
    attr_reader :lists

    def initialize
      @lists = Hash.new { |hash, key| hash[key] = [] }
    end

    def multi
      yield self
    end

    def rpush(key, value)
      lists[key] << value
    end

    def ltrim(key, start_index, stop_index)
      list = lists[key]
      start_index += list.length if start_index.negative?
      stop_index += list.length if stop_index.negative?
      start_index = [start_index, 0].max
      stop_index = [stop_index, list.length - 1].min
      lists[key] = start_index <= stop_index ? list[start_index..stop_index] : []
    end
  end

  let(:redis) { TwitchChatProjectionHandlerSpecRedis.new }
  let(:broadcaster) { class_double(Turbo::StreamsChannel).as_stubbed_const }
  let(:wos_guess_tracker) { instance_double(Wos::ChatGuessTracker, call: nil) }
  let(:handler) do
    described_class.new(
      redis: redis,
      broadcaster: broadcaster,
      wos_guess_tracker: wos_guess_tracker
    )
  end
  let(:event) do
    Orinoco::Pipeline::Event.build(
      "twitch.chat.message_received",
      {
        "tags" => { "display_name" => "Mel" },
        "name" => "mel",
        "txt" => "thank",
        "twitch_emotes" => []
      },
      occurred_at: "2026-07-13T08:15:00Z"
    )
  end

  before do
    allow(broadcaster).to receive(:broadcast_append_to)
  end

  it "persists and renders chat while offering the parsed message to WOS guess tracking" do
    handler.call(event)

    persisted = TwitchChatBridge::Message.from_json(redis.lists.fetch(described_class::HISTORY_KEY).first)
    expect(persisted.txt).to eq("thank")
    expect(broadcaster).to have_received(:broadcast_append_to).with(
      :chat,
      target: "chat_feed",
      layout: false,
      renderable: a_kind_of(ChatMessageComponent)
    )
    expect(wos_guess_tracker).to have_received(:call).with(have_attributes(txt: "thank", display_name: "Mel"))
  end
end
