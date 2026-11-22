# frozen_string_literal: true

require "spec_helper"
require "obs_bridge/obsws_session"

RSpec.describe "Visual calibration OBS commands" do
  let(:req) { double("OBS request client") }
  let(:events) { double("OBS events client") }
  let(:session) { ObsBridge::ObswsSession.new(req: req, events: events) }

  it "returns the transform for an OBS scene item" do
    response = double("response", scene_item_transform: { "sourceWidth" => 1920, "cropLeft" => 100 })
    allow(req).to receive(:get_scene_item_transform).with("Calibration", 12).and_return(response)

    expect(session.apply_request(
      "requestType" => "GetSceneItemTransform",
      "requestData" => { "sceneName" => "Calibration", "sceneItemId" => 12 }
    )).to eq(
      "sceneName" => "Calibration",
      "sceneItemId" => 12,
      "sceneItemTransform" => { "sourceWidth" => 1920, "cropLeft" => 100 }
    )
  end

  it "returns OBS base and output video dimensions" do
    response = double("response", base_width: 1920, base_height: 1200, output_width: 1920, output_height: 1080)
    allow(req).to receive(:get_video_settings).and_return(response)

    expect(session.apply_request(
      "requestType" => "GetVideoSettings", "requestData" => {}
    )).to eq(
      "baseWidth" => 1920, "baseHeight" => 1200,
      "outputWidth" => 1920, "outputHeight" => 1080
    )
  end
end
