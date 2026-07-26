# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TankGame overlay", type: :request do
  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(redis).to receive(:get).with(TankGame::StateStore::KEY).and_return(nil)
  end

  it "renders the transparent TankGame overlay target" do
    get tank_game_overlay_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="tank_game_overlay"')
    expect(response.body).to include('data-controller="tank-game-animation"')
    expect(response.body).to include('data-tank-game-animation-target="volley"')
    expect(response.body).to include("TankGame")
  end
end
