# frozen_string_literal: true

module TwitchChatBridge
  class Message
    attr_accessor :tags, :twitch_emotes, :name, :txt

    def [](key)
      public_send(key.to_sym)
    end
    def []=(key, val)
      public_send("#{key}=",val)
    end

    def initialize(tags:, twitch_emotes: nil, emotes: nil, name:, txt:)
      @tags = tags || {}
      @twitch_emotes = twitch_emotes || emotes || []
      @name = name
      @txt = txt
    end

    def emotes
      twitch_emotes.map do |emote|
        {
          id: emote[:id] || emote["id"],
          url: emote[:url] || emote["url"],
          start: emote[:start] || emote["start"] || emote[:start_idx] || emote["start_idx"],
          end: emote[:end] || emote["end"] || emote[:end_index] || emote["end_index"]
        }
      end
    end

    def display_name
      tags[:display_name].presence || name
    end

    def as_json(*)
      {
        tags: tags,
        twitch_emotes: twitch_emotes,
        emotes: emotes,
        name: name,
        txt: txt,
        display_name: display_name
      }
    end

    def to_json(*args)
      as_json.to_json(*args)
    end

    def self.from_json(json)
      data = JSON.parse(json, symbolize_names: true)

      new(
        tags: data.fetch(:tags, {}),
        twitch_emotes: data.fetch(:twitch_emotes, data.fetch(:emotes, [])),
        name: data.fetch(:name),
        txt: data.fetch(:txt)
      )
    end
  end
end
