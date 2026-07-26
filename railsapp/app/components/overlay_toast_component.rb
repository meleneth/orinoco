# frozen_string_literal: true

class OverlayToastComponent < ApplicationComponent
  def initialize(message:, tone: "info", title: nil)
    @message = message.to_s
    @tone = tone.to_s
    @title = title.to_s.presence
  end

  private

  attr_reader :message, :tone, :title

  def accent_color
    case tone
    when "success"
      "#5ab552"
    when "warning"
      "#f3a833"
    when "danger"
      "#fa6e79"
    else
      "#36c5f4"
    end
  end
end
