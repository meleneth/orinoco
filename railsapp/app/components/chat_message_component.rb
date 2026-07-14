# frozen_string_literal: true

require "uri"

class ChatMessageComponent < ApplicationComponent
  with_collection_parameter :message

  TWITCH_EMOTE_HOST = "static-cdn.jtvnw.net"
  SEVEN_TV_EMOTE_HOST = "cdn.7tv.app"
  SAFE_COLOR_PATTERN = /\A#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?\z/
  DEFAULT_NAME_COLOR = "#ffffff"

  def initialize(message:)
    @message = message
  end

  def display_name
    @message.display_name
  end

  def name_color
    color = tag_value(:color).to_s
    return color if color.match?(SAFE_COLOR_PATTERN)

    DEFAULT_NAME_COLOR
  end

  def rendered_text
    safe_join(rendered_segments)
  end

  private

  def rendered_segments
    replace_seven_tv_emotes(twitch_rendered_segments)
  end

  def twitch_rendered_segments
    text = @message.txt.to_s
    emotes = @message.emotes
      .filter_map { |emote| normalize_twitch_emote(emote, text.length) }
      .sort_by { |emote| emote.fetch(:start) }

    return [ text ] if emotes.empty?

    segments = []
    cursor = 0

    emotes.each do |emote|
      start_index = emote.fetch(:start)
      end_index = emote.fetch(:end)
      next if start_index < cursor

      segments << text[cursor...start_index].to_s
      segments << emote_image(emote.fetch(:url), alt: text[start_index..end_index].to_s, host: TWITCH_EMOTE_HOST)
      cursor = end_index + 1
    end

    segments << text[cursor..].to_s
    segments
  end

  def replace_seven_tv_emotes(segments)
    emotes = seven_tv_emotes
    return segments if emotes.empty?

    segments.flat_map do |segment|
      next segment unless segment.is_a?(String)

      split_text_for_seven_tv(segment).map do |token|
        emote_id = emotes[token]
        emote_id ? seven_tv_image(token, emote_id) : token
      end
    end
  end

  def split_text_for_seven_tv(text)
    text.split(/(\s+)/)
  end

  def seven_tv_emotes
    @seven_tv_emotes ||= redis.hgetall("twitch_emote_7tv").merge(
      redis.hgetall("global_emote_7tv")
    )
  end

  def normalize_twitch_emote(emote, text_length)
    start_index = Integer(emote.fetch(:start))
    end_index = Integer(emote.fetch(:end))
    url = emote.fetch(:url).to_s

    return nil unless start_index >= 0 && end_index >= start_index && end_index < text_length
    return nil unless trusted_emote_url?(url, host: TWITCH_EMOTE_HOST)

    {
      start: start_index,
      end: end_index,
      url: url
    }
  rescue KeyError, ArgumentError, TypeError
    nil
  end

  def seven_tv_image(name, id)
    url_id = ERB::Util.url_encode(id.to_s)
    emote_image("https://#{SEVEN_TV_EMOTE_HOST}/emote/#{url_id}/2x.webp", alt: name, host: SEVEN_TV_EMOTE_HOST)
  end

  def emote_image(url, alt:, host:)
    return "" unless trusted_emote_url?(url, host: host)

    tag.img(src: url, alt: alt, class: "inline-block align-text-bottom")
  end

  def trusted_emote_url?(url, host:)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTPS) && uri.host == host
  rescue URI::InvalidURIError
    false
  end

  def tag_value(key)
    @message.tags[key] || @message.tags[key.to_s]
  end

  def redis
    @redis ||= Redis.new(url: app_config.scoreboard.redis_url)
  end

  def app_config
    Rails.configuration.x
  end
end
