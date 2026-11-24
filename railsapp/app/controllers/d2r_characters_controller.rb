# frozen_string_literal: true

class D2rCharactersController < ApplicationController
  skip_before_action :ensure_obs_config!

  def index
    @characters = D2rCharacter.order(last_seen_at: :desc)
  end

  def show
    @character = D2rCharacter.find(params[:id])
    @runs = @character.d2r_runs.order(started_at: :desc)
    @summary = D2r::ProgressionSummary.call(@runs)
    @observations = @character.d2r_character_observations.order(observed_at: :desc).limit(100)
  end
end
