# frozen_string_literal: true

class D2rActivity < ApplicationRecord
  belongs_to :d2r_run
  belongs_to :d2r_character, optional: true

  validates :kind, :started_at, :boundary_key, presence: true
  validates :boundary_key, uniqueness: true
end
