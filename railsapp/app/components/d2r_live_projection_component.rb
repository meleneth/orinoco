# frozen_string_literal: true

class D2rLiveProjectionComponent < ApplicationComponent
  FIELDS = %w[game level area difficulty terror_zones run events].freeze

  def initialize(state:)
    @state = state.slice(*FIELDS)
  end

  private

  attr_reader :state
end
