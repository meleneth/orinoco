# frozen_string_literal: true

require "rails_helper"

RSpec.describe "D2R browser run log", type: :request do
  let!(:countess) do
    D2rRun.create!(
      game_id: "browser-countess", started_at: Time.iso8601("2026-11-23T10:00:00Z"),
      ended_at: Time.iso8601("2026-11-23T10:03:00Z"),
      run_kind: "countess", run_confidence: 0.9,
      run_evidence: ["Tower Cellar Level 5"],
      steps: [{ "name" => "Black Marsh", "seconds" => 12.5 }],
      loot_sightings: [{ "kind" => "rune", "name" => "Ist Rune", "at" => "2026-11-23T10:02:00Z", "confidence" => "candidate" }],
      events: [{ "type" => "d2r.area.changed", "at" => "2026-11-23T10:01:00Z", "payload" => { "area" => "Black Marsh" } }]
    )
  end
  let!(:other) { D2rRun.create!(game_id: "browser-other", started_at: Time.iso8601("2026-11-22T10:00:00Z"), run_kind: "andy") }

  it "renders a navigable, newest-first run listing" do
    get "/d2r/log"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Diablo II", "Countess", "Andy", "browser-countess").or include("Diablo II", "Countess", "Andy")
    expect(response.body.index("Countess")).to be < response.body.index("Andy")
  end

  it "filters by inferred run kind" do
    get "/d2r/log", params: { kind: "countess" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Countess")
    expect(response.body).not_to include("Andy")
  end

  it "shows run splits, sighted loot, classification evidence, and events" do
    get "/d2r/log/#{countess.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Black Marsh", "Ist Rune", "Tower Cellar Level 5", "d2r.area.changed")
    expect(response.body).to include("not confirmed picked up")
  end

  it "returns not found for an absent run" do
    get "/d2r/log/999999999"
    expect(response).to have_http_status(:not_found)
  end
end
