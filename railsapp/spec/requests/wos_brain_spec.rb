# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe "WOSBrain", type: :request do
  class WosBrainRequestSpecRedis
    def initialize(values = {})
      @values = values
    end

    def get(key)
      @values[key]
    end
  end

  let(:redis) do
    WosBrainRequestSpecRedis.new(
      Wos::StatusStore::KEY => JSON.generate(
        "state" => "recognized",
        "screenshot_source_name" => "Display Capture",
        "last_request_id" => "req-1",
        "last_capture_requested_at" => "2026-07-13T08:00:00.000000Z",
        "last_recognized_at" => "2026-07-13T08:00:02.000000Z",
        "last_projected_at" => "2026-07-13T08:00:03.000000Z",
        "last_error" => ""
      ),
      Wos::OverlayStateStore::KEY => JSON.generate(
        "recognized_at" => "2026-07-13T08:00:02.000000Z",
        "recognition" => {
          "ruleset" => { "mode" => "base" },
          "letters" => [
            { "index" => 0, "char" => "W" },
            { "index" => 1, "char" => "O" },
            { "index" => 2, "char" => "S" }
          ]
        }
      )
    )
  end

  before do
    AffordanceConfig.fetch!(:wos_brain).update!(
      enabled: true,
      config: AffordanceConfig.default_config_for(:wos_brain).merge(
        "enabled" => true,
        "screenshot_source_name" => "Display Capture",
        "ruleset_mode" => "manual",
        "manual_ruleset" => "base"
      )
    )
    allow(Redis).to receive(:new).and_return(redis)
  end

  it "renders WOSBrain configuration, runtime status, and latest projection" do
    get wos_brain_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("WOSBrain")
    expect(response.body).to include("Display Capture")
    expect(response.body).to include("recognized")
    expect(response.body).to include("2026-07-13T08:00:03.000000Z")
    expect(response.body).to include("req-1")
    expect(response.body).to include("WOS")
    expect(response.body).to include("Open /overlay")
  end
end
