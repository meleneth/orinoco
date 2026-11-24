# frozen_string_literal: true

class D2rCharacter < ApplicationRecord
  has_many :d2r_runs, dependent: :restrict_with_exception
  has_many :d2r_character_observations, dependent: :restrict_with_exception

  validates :name, :character_class, :first_seen_at, :last_seen_at, presence: true
end
