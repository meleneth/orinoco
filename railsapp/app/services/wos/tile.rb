# frozen_string_literal: true

module Wos
  Tile = Data.define(:index, :region, :state, :char, :confidence, :metrics) do
    def to_h
      {
        index: index,
        region: region.to_h,
        state: state,
        char: char,
        confidence: confidence,
        metrics: metrics
      }
    end
  end
end
