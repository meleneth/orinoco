# frozen_string_literal: true

class D2rCharacter < ApplicationRecord
  has_many :d2r_runs, dependent: :restrict_with_exception
  has_many :d2r_character_observations, dependent: :restrict_with_exception
  has_many :d2r_activities, dependent: :restrict_with_exception
  has_many :d2r_time_intervals, dependent: :restrict_with_exception
  has_many :d2r_act_milestones, dependent: :restrict_with_exception

  validates :identity_key, :name, :character_class, :first_seen_at, :last_seen_at, presence: true
  validates :identity_key, uniqueness: true
end
