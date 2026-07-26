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
  it "renders parseable volley JSON for the animation controller" do
    allow(redis).to receive(:get).with(TankGame::StateStore::KEY).and_return(
      JSON.generate(
        "phase" => "active",
        "status" => "Volley fired",
        "last_volley" => {
          "id" => "volley-1",
          "shots" => []
        }
      )
    )

    get tank_game_overlay_path

    expect(response.body).to include('{"id":"volley-1"')
    expect(response.body).not_to include('{&quot;id&quot;')
  end
end
