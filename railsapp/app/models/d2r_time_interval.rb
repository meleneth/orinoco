# frozen_string_literal: true

class D2rTimeInterval < ApplicationRecord
  KINDS = %w[in_game_town in_game_field outside_game unknown].freeze

  belongs_to :d2r_run, optional: true
  belongs_to :d2r_character, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :started_at, :ended_at, :seconds, :fingerprint, presence: true
  validates :fingerprint, uniqueness: true
end
