# frozen_string_literal: true

require "faye/websocket"
# require "net/http"

module TwitchChatBridge
  class IrcMessageParser
    def initialize(channel_name:, bot_name:)
      @channel_name = channel_name
      @bot_name = bot_name
    end

    def parse(line)
      rest = line.chomp
      tags = {}

      if rest.start_with?("@")
        raw_tags, rest = rest.split(" ", 2)
        return nil if rest.blank?

        tags = parse_twitch_tags(raw_tags[1..])
      end

      return nil unless rest.start_with?(":")

      raw_prefix, rest = rest.split(" ", 2)
      return nil if raw_prefix.blank? || rest.blank?
      return nil unless raw_prefix.include?("@")

      name_start = raw_prefix.index("@") + 1
      name_end = raw_prefix.index(".", name_start)
      return nil unless name_end

      name = raw_prefix[name_start...name_end]

      channel_idx = rest.downcase.index(@channel_name.downcase)
      return nil unless channel_idx

      msg_idx = channel_idx + @channel_name.length + 2

      return nil if [
        ":tmi",
        @bot_name,
        ":#{@bot_name}"
      ].include?(name)

      return nil if name.include?("@emote-only=0;")

      TwitchChatBridge::Message.new(
        tags: tags,
        twitch_emotes: tags[:twitch_emotes],
        name: name,
        txt: rest[msg_idx..]
      )
    end


    def parse_twitch_tags(raw_tags)
      parsed_tags = {}

      raw_tags.split(";").each do |pair|
        key, val = pair.split("=", 2)
        tag_val = val.presence

        case key
        when "emotes"
          parsed_tags[:twitch_emotes] = parse_emotes_tag(tag_val)
        when "color"
          parsed_tags[:color] = tag_val.presence || "pink"
        when "display-name"
          parsed_tags[:display_name] = tag_val
        when "subscriber"
          parsed_tags[:subscriber] = tag_val == "1"
        when "mod"
          parsed_tags[:mod] = tag_val == "1"
        when "badges"
          parsed_tags[:badges] = parse_badges_tag(tag_val)
        when "custom-reward-id"
          parsed_tags[:custom_reward_id] = tag_val
        when "user-id"
          parsed_tags[:user_id] = tag_val
        end
      end

      parsed_tags
    end

    def parse_badges_tag(tag_val)
      return [] if tag_val.blank?

      tag_val.split(",").filter_map do |badge|
        name, _version = badge.split("/", 2)
        name.presence
      end
    end

    def parse_emotes_tag(tag_val)
      return nil if tag_val.blank?
      emote_list = []

      # QTODO: Change
      # "tag_val.split("/", -1).each do |emote|"
      # to
      # "for emote in tag_val.split("/", -1)"
      # and see if I like it
      tag_val.split("/", -1).each do |emote|
        emote_id, raw_positions = emote.split(":", 2)
        next if emote_id.blank? || raw_positions.blank?

        emote_id = ERB::Util.url_encode(emote_id)

        cdn_url = "https://static-cdn.jtvnw.net/emoticons/v2/"
        out_url = "#{cdn_url}#{emote_id}/default/dark/2.0"

        raw_positions.split(",").each do |position|
          start_position, end_position = position.split("-", 2)
          emote_list.push({
            id:        emote_id,
            url:       out_url,
            start_idx: start_position.to_i,
            end_index: end_position.to_i
          })
        end
      end

      # Rails.logger = ActiveSupport::Logger.new($stdout)
      # Rails.logger.level = Logger::INFO
      # Rails.logger.info("DEBUG #{emote_list.sort_by { |h| h[:end_index] }}")

      emote_list.sort_by { |h| h[:end_index] }
    end

    def unescape_tag_value(value)
      return true if value.nil?

      value
        .gsub("\\s", " ")
        .gsub("\\r", "\r")
        .gsub("\\n", "\n")
        .gsub("\\\\", "\\")
    end
  end
end
