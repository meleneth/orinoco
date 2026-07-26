# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/string/inflections"
require "obs_bridge/obsws_session"

RSpec.describe ObsBridge::ObswsSession do
  let(:req) { instance_double("obs request client") }
  let(:events) { instance_double("obs events client", close: nil) }

  subject(:session) do
    described_class.new(req: req, events: events)
  end

  it "closes the events client when the session closes" do
    session.close

    expect(events).to have_received(:close).once
  end
  it "captures the current program scene when no source is provided" do
    current_scene = double("current scene response", current_program_scene_name: "Gameplay")
    screenshot = double("screenshot response", image_data: "data:image/png;base64,abc")

    allow(req).to receive(:get_current_program_scene).and_return(current_scene)
    allow(req).to receive(:get_source_screenshot)
      .with("Gameplay", "png", 1280, 720, -1)
      .and_return(screenshot)

    result = session.apply_request(
      "requestType" => "GetSourceScreenshot",
      "requestData" => {}
    )

    expect(result).to include(
      "imageData" => "data:image/png;base64,abc",
      "imageFormat" => "png",
      "sourceName" => "Gameplay",
      "activeSceneName" => "Gameplay",
      "imageWidth" => 1280,
      "imageHeight" => 720
    )
  end

  it "captures a named source when provided" do
    current_scene = double("current scene response", current_program_scene_name: "Gameplay")
    screenshot = double("screenshot response", image_data: "data:image/jpeg;base64,abc")

    allow(req).to receive(:get_current_program_scene).and_return(current_scene)
    allow(req).to receive(:get_source_screenshot)
      .with("Board", "jpg", 640, 360, 80)
      .and_return(screenshot)

    result = session.apply_request(
      "requestType" => "GetSourceScreenshot",
      "requestData" => {
        "sourceName" => "Board",
        "imageFormat" => "jpg",
        "imageWidth" => 640,
        "imageHeight" => 360,
        "imageCompressionQuality" => 80
      }
    )

    expect(result).to include(
      "imageData" => "data:image/jpeg;base64,abc",
      "imageFormat" => "jpg",
      "sourceName" => "Board",
      "activeSceneName" => "Gameplay",
      "imageWidth" => 640,
      "imageHeight" => 360,
      "imageCompressionQuality" => 80
    )
  end
  it "applies TankGame scene setup requests" do
    allow(req).to receive(:create_scene).with("TankGame")
    allow(req).to receive(:create_scene_item).with("TankGame", "Gameplay", true)
    allow(req).to receive(:create_input).with(
      "TankGame",
      "TankGameWebView",
      "browser_source",
      { "url" => "http://localhost:31050/tank_game/overlay", "width" => 1920, "height" => 1080 },
      true
    )
    allow(req).to receive(:set_current_program_scene).with("TankGame")

    session.apply_request("requestType" => "CreateScene", "requestData" => { "sceneName" => "TankGame" })
    session.apply_request("requestType" => "CreateSceneItem", "requestData" => { "sceneName" => "TankGame", "sourceName" => "Gameplay" })
    session.apply_request(
      "requestType" => "CreateInput",
      "requestData" => {
        "sceneName" => "TankGame",
        "inputName" => "TankGameWebView",
        "inputKind" => "browser_source",
        "inputSettings" => { "url" => "http://localhost:31050/tank_game/overlay", "width" => 1920, "height" => 1080 }
      }
    )
    session.apply_request("requestType" => "SetCurrentProgramScene", "requestData" => { "sceneName" => "TankGame" })

    expect(req).to have_received(:create_scene)
    expect(req).to have_received(:create_scene_item)
    expect(req).to have_received(:create_input)
    expect(req).to have_received(:set_current_program_scene)
  end

  it "returns the current program scene" do
    current_scene = double("current scene response", current_program_scene_name: "Gameplay")
    allow(req).to receive(:get_current_program_scene).and_return(current_scene)

    result = session.apply_request(
      "requestType" => "GetCurrentProgramScene",
      "requestData" => {}
    )

    expect(result).to eq("currentProgramSceneName" => "Gameplay")
  end
end
