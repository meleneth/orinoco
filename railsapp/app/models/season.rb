# frozen_string_literal: true

class Season < ApplicationRecord
  belongs_to :game_definition
  has_many :loot_drops, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :game_definition_id }
  validates :active, inclusion: { in: [ true, false ] }
end
