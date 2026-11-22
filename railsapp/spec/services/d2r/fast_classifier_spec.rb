# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "d2r/fast_classifier"

RSpec.describe D2r::FastClassifier do
  let(:fixture_root) { Pathname(__dir__).join("../../fixtures/files/d2r").expand_path }
  let(:truth) { YAML.safe_load_file(fixture_root.join("truth.yml")) }

  it "classifies every held-out fixture into independent screen, panel, and tooltip signals" do
    failures = truth.fetch("fixtures").select { |fixture| fixture.fetch("split") == "holdout" }.filter_map do |fixture|
      result = described_class.new.call(fixture_root.join(fixture.fetch("file")))
      actual = result.signals.transform_values { |signal| signal.fetch("state") }
      [ fixture.fetch("file"), fixture.fetch("signals"), actual ] unless actual == fixture.fetch("signals")
    end

    expect(failures).to be_empty
  end

  it "reports classification latency" do
    result = described_class.new.call(fixture_root.join("death_screen_holdout.jpg"))

    expect(result.elapsed_ms).to be >= 0
  end
end
