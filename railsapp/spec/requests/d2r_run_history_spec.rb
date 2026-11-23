# frozen_string_literal: true

require "rails_helper"

RSpec.describe "D2R run history", type: :request do
  let!(:older) do
    D2rRun.create!(game_id: "old", started_at: Time.iso8601("2026-11-22T10:00:00Z"),
      run_kind: "countess", events: [ { "type" => "d2r.game.started" } ])
  end
  let!(:newer) do
    D2rRun.create!(game_id: "new", started_at: Time.iso8601("2026-11-23T10:00:00Z"),
      run_kind: "andy")
  end

  it "paginates newest first without sending all event payloads" do
    get "/d2r/runs", params: { limit: 1, page: 1 }
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.fetch("total")).to eq(2)
    expect(body.fetch("runs").map { |run| run.fetch("game_id") }).to eq([ "new" ])
    expect(body.dig("runs", 0, "events")).to eq([])

    get "/d2r/runs", params: { limit: 1, page: 2 }
    expect(response.parsed_body.dig("runs", 0, "game_id")).to eq("old")
  end

  it "filters by run kind and returns the full event record on detail" do
    get "/d2r/runs", params: { kind: "countess" }
    expect(response.parsed_body.fetch("total")).to eq(1)
    get "/d2r/runs/#{older.id}"
    expect(response.parsed_body.fetch("events").first.fetch("type")).to eq("d2r.game.started")
  end
end
