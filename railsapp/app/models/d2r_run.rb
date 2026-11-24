# frozen_string_literal: true

class D2rRun < ApplicationRecord
  belongs_to :d2r_character, optional: true
  has_many :loot_drops, dependent: :restrict_with_exception

  validates :game_id, presence: true, uniqueness: true
  validates :started_at, presence: true

  scope :recent_first, -> { order(started_at: :desc, id: :desc) }

  def outcome
    D2r::RunOutcome.call(self)
  end

  def as_history_json(include_events: true)
    {
      id: id, game_id: game_id, started_at: started_at, ended_at: ended_at, outcome: outcome,
      run_started_at: run_started_at, run_kind: run_kind, repeated: repeated,
      run_confidence: run_confidence, run_evidence: run_evidence,
      loot_sightings: loot_sightings,
      character_level: character_level, area: area, difficulty: difficulty,
      terror_zones: terror_zones, steps: steps, current_step: current_step,
      events: include_events ? events : [], screen: screen,
      duration_seconds: [ ((ended_at || last_event_at || started_at) - started_at).round(3), 0 ].max
    }
  end
end
