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
    expect(response.body).to include("[tank-game:fallback]")
    expect(response.body).to include("/tank_game/state")
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

  it "serves the current TankGame state as JSON for the overlay fallback poller" do
    allow(redis).to receive(:get).with(TankGame::StateStore::KEY).and_return(
      JSON.generate(
        "phase" => "active",
        "status" => "Volley fired",
        "last_volley" => {
          "id" => "volley-2",
          "shots" => [
            {
              "shooter" => "morningstar",
              "points" => [{ "x" => 100, "y" => 700 }, { "x" => 220, "y" => 650 }]
            }
          ]
        }
      )
    )

    get tank_game_state_path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body).to include(
      "phase" => "active",
      "status" => "Volley fired"
    )
    expect(response.parsed_body.dig("last_volley", "id")).to eq("volley-2")
  end
end
