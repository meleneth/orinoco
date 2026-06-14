# frozen_string_literal: true

require "rails_helper"

RSpec.describe Overlay::TimerConfig do
  it "serializes countdown state for templates" do
    config = described_class.new(
      timer_key: "clip_countdown",
      duration_ms: 30_000,
      mode: "countdown",
      starts_on: "clip_show.started",
      stops_on: "clip_show.ended",
      tick_rate_ms: 250
    )

    expect(config).to be_valid
    expect(config.serializable_state).to eq(
      "timer_key" => "clip_countdown",
      "duration_ms" => 30_000,
      "mode" => "countdown",
      "starts_on" => "clip_show.started",
      "stops_on" => "clip_show.ended",
      "tick_rate_ms" => 250,
      "remaining_ms" => 30_000,
      "remaining_label" => "00:30"
    )
  end

  it "rejects unknown timer modes" do
    config = described_class.new(
      timer_key: "clip_countdown",
      duration_ms: 30_000,
      mode: "countup",
      starts_on: "clip_show.started",
      stops_on: "clip_show.ended",
      tick_rate_ms: 250
    )

    expect(config).not_to be_valid
    expect(config.validation_errors.join(" ")).to include("mode is invalid")
  end
end
