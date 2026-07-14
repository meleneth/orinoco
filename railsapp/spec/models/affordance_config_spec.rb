# frozen_string_literal: true

require "rails_helper"

RSpec.describe AffordanceConfig, type: :model do
  describe ".fetch!" do
    it "creates WOSBrain config disabled with automatic base ruleset defaults" do
      config = described_class.fetch!(:wos_brain)

      expect(config).not_to be_enabled
      expect(config.ruleset_mode).to eq("auto")
      expect(config.manual_ruleset).to eq("base")
      expect(config.screenshot_source_name).to eq("")
      expect(config.scenes).to eq([])
    end
  end

  describe "normalization" do
    it "normalizes unsupported WOSBrain ruleset values to safe defaults" do
      config = described_class.create!(
        name: "wos_brain",
        config: {
          "enabled" => true,
          "ruleset_mode" => "surprise",
          "manual_ruleset" => "unknown",
          "screenshot_source_name" => " Display Capture "
        }
      )

      expect(config).to be_enabled
      expect(config.ruleset_mode).to eq("auto")
      expect(config.manual_ruleset).to eq("base")
      expect(config.screenshot_source_name).to eq("Display Capture")
    end
  end
end