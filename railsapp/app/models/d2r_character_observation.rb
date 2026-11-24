# frozen_string_literal: true

class D2rCharacterObservation < ApplicationRecord
  belongs_to :d2r_character
  belongs_to :d2r_run, optional: true
  validates :fingerprint, :kind, :observed_at, presence: true
end
