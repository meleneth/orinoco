# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2rCharacter, type: :model do
  def attributes(identity_key)
    {
      identity_key:,
      name: "RepeatedName",
      character_class: "Sorceress",
      first_seen_at: Time.iso8601("2026-11-23T10:00:00Z"),
      last_seen_at: Time.iso8601("2026-11-23T10:00:00Z")
    }
  end

  it "keeps distinct identities even when name and class match" do
    first = described_class.create!(attributes("roster-slot-a"))
    second = described_class.create!(attributes("roster-slot-b"))

    expect(second).not_to eq(first)
    expect(described_class.where(name: "RepeatedName", character_class: "Sorceress").count).to eq(2)
  end

  it "rejects reuse of an observed identity key" do
    described_class.create!(attributes("roster-slot-a"))

    expect(described_class.new(attributes("roster-slot-a"))).not_to be_valid
  end
end
