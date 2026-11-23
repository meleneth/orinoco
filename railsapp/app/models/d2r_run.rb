# frozen_string_literal: true

class D2rRun < ApplicationRecord
  validates :game_id, presence: true, uniqueness: true
  validates :started_at, presence: true

  scope :recent_first, -> { order(started_at: :desc, id: :desc) }

  def as_history_json
    {
      id: id, game_id: game_id, started_at: started_at, ended_at: ended_at,
      run_started_at: run_started_at, run_kind: run_kind, repeated: repeated,
      character_level: character_level, area: area, difficulty: difficulty,
      terror_zones: terror_zones, steps: steps, current_step: current_step,
      events: events, screen: screen,
      duration_seconds: ((ended_at || Time.current) - started_at).round(3)
    }
  end
end
