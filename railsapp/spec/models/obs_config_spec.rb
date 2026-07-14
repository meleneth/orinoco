# frozen_string_literal: true

require "rails_helper"

RSpec.describe ObsConfig, type: :model do
  it "defaults to the Docker host gateway hostname" do
    config = described_class.new

    expect(config.host).to eq("host.docker.internal")
    expect(config.port).to eq(4455)
  end

  it "requires a host and valid websocket port" do
    config = described_class.new(host: "", port: 70_000)

    expect(config).not_to be_valid
    expect(config.errors[:host]).to be_present
    expect(config.errors[:port]).to be_present
  end
end