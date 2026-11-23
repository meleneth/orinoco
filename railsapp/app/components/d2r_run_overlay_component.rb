# frozen_string_literal: true

class D2rRunOverlayComponent < ApplicationComponent
  def initialize(state: nil)
    @state = state || {}
  end

  private

  attr_reader :state
end
