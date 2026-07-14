# frozen_string_literal: true

require "spec_helper"
require "interaction_demo/obs_setup"

RSpec.describe InteractionDemo::ObsSetup do
  class ObsSetupSpecInventory
    def scenes
      [ { "sceneName" => InteractionDemo::ObsSetup::SCENE_NAME } ]
    end

    def scene_items(_scene_name)
      [
        {
          "sourceName" => InteractionDemo::ObsSetup::WEB_SOURCE_NAME,
          "sourceUuid" => "web-source-uuid",
          "sceneItemId" => 42
        }
      ]
    end

    def placements_for_input_uuid(input_uuid)
      return [] unless input_uuid == "web-source-uuid"

      [
        { "sceneName" => InteractionDemo::ObsSetup::SCENE_NAME, "sceneItemId" => 42 },
        { "sceneName" => "[Scene]DesktopHacking", "sceneItemId" => 8 }
      ]
    end
  end

  let(:inventory_reader) { ObsSetupSpecInventory.new }
  let(:control_publisher) { double(refresh!: true) }
  let(:published_requests) { [] }
  let(:command_publisher) do
    double.tap do |publisher|
      allow(publisher).to receive(:publish!) { |request| published_requests << request }
    end
  end

  it "configures the existing OBS browser source to the canonical overlay URL" do
    described_class.new(
      inventory_reader: inventory_reader,
      control_publisher: control_publisher,
      command_publisher: command_publisher,
      external_base_url: "http://localhost:33230",
      sleeper: ->(_seconds) {}
    ).call

    input_settings_request = published_requests.find { |request| request.fetch("requestType") == "SetInputSettings" }
    expect(input_settings_request.dig("requestData", "inputName")).to eq(InteractionDemo::ObsSetup::WEB_SOURCE_NAME)
    expect(input_settings_request.dig("requestData", "inputSettings", "url")).to eq("http://localhost:33230/overlay")

    transform_requests = published_requests.select { |request| request.fetch("requestType") == "SetSceneItemTransform" }
    expect(transform_requests.map { |request| request.dig("requestData", "sceneName") }).to eq([
      InteractionDemo::ObsSetup::SCENE_NAME,
      "[Scene]DesktopHacking"
    ])
    expect(transform_requests.map { |request| request.dig("requestData", "sceneItemId") }).to eq([42, 8])
    expect(transform_requests).to all(satisfy do |request|
      request.dig("requestData", "sceneItemTransform", "boundsWidth") == 1920 &&
        request.dig("requestData", "sceneItemTransform", "boundsHeight") == 1080
    end)
  end
end
