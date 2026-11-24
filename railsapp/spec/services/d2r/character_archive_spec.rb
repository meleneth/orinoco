# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2r::CharacterArchive do
  def event(identity_key, occurred_at: "2026-11-23T10:00:00Z")
    Orinoco::Pipeline::Event.build(
      "d2r.character.selected",
      {
        "identity_key" => identity_key,
        "name" => "RepeatedName",
        "character_class" => "Sorceress",
        "level" => 12,
        "ladder" => true,
        "season" => "Season 12"
      },
      occurred_at:
    )
  end

  it "archives matching names and classes as distinct observed identities" do
    first = event("roster-a")
    second = event("roster-b", occurred_at: "2026-11-23T10:01:00Z")

    described_class.new.call(first, "character" => first.payload)
    described_class.new.call(second, "character" => second.payload)

    expect(D2rCharacter.where(name: "RepeatedName", character_class: "Sorceress").pluck(:identity_key)).to contain_exactly(
      "roster-a", "roster-b"
    )
  end

  it "associates the active game with its projected identity" do
    selected = event("roster-active")
    run = D2rRun.create!(game_id: "identity-game", started_at: Time.iso8601("2026-11-23T10:00:00Z"))
    state = {
      "character" => selected.payload,
      "game" => { "id" => run.game_id, "ended_at" => nil }
    }

    described_class.new.call(selected, state)

    expect(run.reload.d2r_character.identity_key).to eq("roster-active")
  end
end
