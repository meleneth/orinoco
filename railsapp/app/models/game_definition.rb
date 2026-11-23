# frozen_string_literal: true

class GameDefinition < ApplicationRecord
  has_many :seasons, dependent: :restrict_with_exception

  validates :name, :publisher, :link, presence: true
  validates :year, presence: true, numericality: { only_integer: true, greater_than: 1900 }
  validates :name, uniqueness: { scope: %i[publisher year] }
end
