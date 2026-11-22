# frozen_string_literal: true

require "spec_helper"
require "visual_observer/calibration"

RSpec.describe VisualObserver::Calibration do
  let(:transform) do
    {
      "sourceWidth" => 1920,
      "sourceHeight" => 1200,
      "cropLeft" => 960,
      "cropRight" => 480,
      "cropTop" => 100,
      "cropBottom" => 900,
      "positionX" => 250,
      "positionY" => 150,
      "scaleX" => 1.5,
      "scaleY" => 1.5
    }
  end

  def import(transform:)
    described_class.import(
      scene_name: "Calibration",
      scene_item_id: 7,
      source_name: "D2R",
      transform: transform,
      reference_width: 1920,
      reference_height: 1200
    )
  end

  it "extracts source-relative crop geometry without confusing it with OBS placement" do
    result = import(transform: transform)
    expect(result.fetch("rect")).to eq(
      "x" => 0.5, "y" => (100.0 / 1200), "width" => 0.25, "height" => (200.0 / 1200)
    )
    expect(result.fetch("transform")).to eq(transform)
  end

  it "uses the whole source when no crop was configured" do
    result = import(transform: transform.except("cropLeft", "cropRight", "cropTop", "cropBottom"))
    expect(result.fetch("rect")).to eq("x" => 0.0, "y" => 0.0, "width" => 1.0, "height" => 1.0)
  end

  it "rejects invalid crop rectangles" do
    expect { import(transform: transform.merge("cropRight" => 960)) }.to raise_error(described_class::Invalid)
  end

  it "rejects missing source dimensions" do
    expect { import(transform: transform.except("sourceWidth")) }.to raise_error(described_class::Invalid)
  end
end
