# frozen_string_literal: true

class D2rActMilestone < ApplicationRecord
  STATUSES = %w[inferred confirmed].freeze

  belongs_to :d2r_character

  validates :difficulty, :observed_at, presence: true
  validates :act, inclusion: { in: 1..5 }
  validates :status, inclusion: { in: STATUSES }
  validates :act, uniqueness: { scope: [:d2r_character_id, :difficulty] }
end
