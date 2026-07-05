# frozen_string_literal: true

class ChatMessageComponent < ApplicationComponent
  with_collection_parameter :message
  def redis
    @redis ||= Redis.new(url: app_config.scoreboard.redis_url)
  end
  def app_config
    Rails.configuration.x
  end

  def initialize(message:)
    @message = message

    #parse twitch emotes
    #QTODO: need to parse twitch emotes FIRST
    #       but these checks need to go away or be replaced
    if (message[:twitch_emotes])
      if (message[:twitch_emotes][0])
        parts = []
        last_idx = message[:txt].length
        message[:twitch_emotes].reverse_each do |emote|
          url       = emote[:url]
          start_idx = emote[:start_idx]
          end_index = emote[:end_index]

          last_half = message[:txt].slice(end_index+1...last_idx)

          parts.unshift(last_half)
          parts.unshift("<img src='#{url}' style='display: inline;'>".html_safe)
          last_idx = start_idx
        end

        parts.unshift(message[:txt].slice(0...last_idx))
        @message[:txt] = safe_join(parts)
      end
    end


    #parse 7tv emotes
    #QTODO: some emotes are "zero-width", which I guess means they can stack on top of each other
    #       no clue how to do this yet, or even how to detect if they are supposed to be able to
    r = redis
    twitch_emote_7tv = r.hgetall("twitch_emote_7tv")
    global_emote_7tv = r.hgetall("global_emote_7tv")

    # split_txt = @message[:txt].split
    # split_txt.each do |word|
    #   url_id = twitch_emote_7tv["#{word}"]
    #   if (url_id)
    #     word = "<img src='https://cdn.7tv.app/emote/#{url_id}/2x.webp' style='display: inline;'>".html_safe
    #     url_id = nil
    #   end
    #   url_id = global_emote_7tv["#{word}"]
    #   if (url_id)
    #     word = "<img src='https://cdn.7tv.app/emote/#{url_id}/2x.webp' style='display: inline;'>".html_safe
    #     url_id = nil
    #   end
    #   @message[:txt] = safe_join(split_txt, " ")
    # end

    twitch_emote_7tv.each do |name, id|
      url_id = ERB::Util.url_encode(id)
      @message[:txt].gsub!(/\b#{Regexp.escape(name)}\b/, "<img src='https://cdn.7tv.app/emote/#{url_id}/2x.webp' style='display: inline;'>".html_safe)
    end
    global_emote_7tv.each do |name, id|
      # puts("global emote name: #{name}")
      url_id = ERB::Util.url_encode(id)
      @message[:txt].gsub!(/\b#{Regexp.escape(name)}\b/, "<img src='https://cdn.7tv.app/emote/#{url_id}/2x.webp' style='display: inline;'>".html_safe)
    end

  end
end
