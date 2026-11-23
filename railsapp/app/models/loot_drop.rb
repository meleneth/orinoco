# frozen_string_literal: true

class LootDrop < ApplicationRecord
  belongs_to :season
  belongs_to :d2r_run

  validates :kind, :name, :confidence, :observed_at, :event_fingerprint, presence: true
  validates :event_fingerprint, uniqueness: true
end
