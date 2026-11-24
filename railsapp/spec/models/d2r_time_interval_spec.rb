# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2rTimeInterval, type: :model do
  it "requires an explicit observed-time classification" do
    interval = described_class.new(
      kind: "between_guesses",
      started_at: Time.iso8601("2026-11-23T10:00:00Z"),
      ended_at: Time.iso8601("2026-11-23T10:00:01Z"),
      seconds: 1,
      fingerprint: "invalid-kind"
    )

    expect(interval).not_to be_valid
  end
end
