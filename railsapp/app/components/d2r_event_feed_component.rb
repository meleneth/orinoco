# frozen_string_literal: true

class D2rEventFeedComponent < ApplicationComponent
  def initialize(events:)
    @events = Array(events).first(D2r::RunProjection::HISTORY_LIMIT)
  end

  private

  attr_reader :events
end
