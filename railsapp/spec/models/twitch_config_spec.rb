# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwitchConfig, type: :model do
  it "requires a channel name" do
    config = described_class.new(channel_name: "")

    expect(config).not_to be_valid
    expect(config.errors[:channel_name]).to be_present
  end
end