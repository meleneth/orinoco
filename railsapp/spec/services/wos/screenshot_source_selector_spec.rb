# frozen_string_literal: true

require "spec_helper"
require "wos/screenshot_source_selector"

RSpec.describe Wos::ScreenshotSourceSelector do
  it "prefers display and desktop-like source names" do
    selector = described_class.new(["Browser", "Mic/Aux", "Display Capture"])

    expect(selector.call).to eq("Display Capture")
  end

  it "ignores blank duplicates" do
    selector = described_class.new(["", " Desktop ", "Desktop"])

    expect(selector.call).to eq("Desktop")
  end
end