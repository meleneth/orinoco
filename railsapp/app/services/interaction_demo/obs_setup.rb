# frozen_string_literal: true

module InteractionDemo
  class ObsSetup
    SCENE_NAME = "Orinoco"
    WEB_SOURCE_NAME = "OrinocoWebView"
    WEB_SOURCE_KIND = "browser_source"
    WEB_WIDTH = 1920
    WEB_HEIGHT = 1080

    def initialize(
      inventory_reader:,
      control_publisher:,
      command_publisher:,
      external_base_url:,
      scene_name: SCENE_NAME,
      web_source_name: WEB_SOURCE_NAME,
      placement_scene_names: [ scene_name ],
      sleeper: ->(seconds) { sleep seconds }
    )
      @inventory_reader = inventory_reader
      @control_publisher = control_publisher
      @command_publisher = command_publisher
      @external_base_url = external_base_url
      @scene_name = scene_name
      @web_source_name = web_source_name
      @placement_scene_names = placement_scene_names
      @sleeper = sleeper
    end

    def call
      refresh_inventory!

      create_scene_unless_present!
      refresh_inventory!

      create_web_source_unless_present!
      refresh_inventory!
      create_web_source_placements!
      configure_web_source!
      refresh_web_source!
      refresh_inventory!
      fit_web_source_to_scene_items!
      refresh_inventory!
    end

    private

    attr_reader :inventory_reader, :control_publisher, :command_publisher, :external_base_url,
      :scene_name, :web_source_name, :placement_scene_names, :sleeper

    def create_scene_unless_present!
      return if scene_names.include?(scene_name)

      command_publisher.publish!(
        "requestType" => "CreateScene",
        "requestData" => {
          "sceneName" => scene_name
        }
      )
    end

    def create_web_source_unless_present!
      return if web_source_present?

      command_publisher.publish!(
        "requestType" => "CreateInput",
        "requestData" => {
          "sceneName" => scene_name,
          "inputName" => web_source_name,
          "inputKind" => WEB_SOURCE_KIND,
          "inputSettings" => input_settings,
          "sceneItemEnabled" => true
        }
      )
    end

    def create_web_source_placements!
      placement_scene_names.each do |placement_scene_name|
        next unless scene_names.include?(placement_scene_name)
        next if scene_has_web_source?(placement_scene_name)

        command_publisher.publish!(
          "requestType" => "CreateSceneItem",
          "requestData" => {
            "sceneName" => placement_scene_name,
            "sourceName" => web_source_name,
            "sceneItemEnabled" => true,
            "sceneItemTransform" => web_source_transform
          }
        )
      end
    end

    def configure_web_source!
      command_publisher.publish!(
        "requestType" => "SetInputSettings",
        "requestData" => {
          "inputName" => web_source_name,
          "inputSettings" => input_settings,
          "overlay" => true
        }
      )
    end

    def refresh_web_source!
      command_publisher.publish!(
        "requestType" => "PressInputPropertiesButton",
        "requestData" => {
          "inputName" => web_source_name,
          "propertyName" => "refreshnocache"
        }
      )
    end

    def fit_web_source_to_scene_items!
      web_source_placements.each do |placement|
        command_publisher.publish!(
          "requestType" => "SetSceneItemTransform",
          "requestData" => {
            "sceneName" => placement.fetch("sceneName"),
            "sceneItemId" => placement.fetch("sceneItemId"),
            "sceneItemTransform" => web_source_transform
          }
        )
      end
    end
    def refresh_inventory!
      control_publisher.refresh!
      sleeper.call(1.0)
    end

    def scene_names
      inventory_reader.scenes.map { |scene| scene.fetch("sceneName") }
    rescue KeyError
      []
    end

    def web_source_present?
      scene_has_web_source?(scene_name)
    end

    def scene_has_web_source?(candidate_scene_name)
      inventory_reader.scene_items(candidate_scene_name).any? do |item|
        item["sourceName"] == web_source_name
      end
    end

    def web_source_placements
      source_item = inventory_reader.scene_items(scene_name).find do |item|
        item["sourceName"] == web_source_name
      end
      return [] unless source_item

      placements = inventory_reader.placements_for_input_uuid(source_item.fetch("sourceUuid", nil))
      return placements if placements.any?

      [ source_item.merge("sceneName" => scene_name) ]
    end

    def web_source_transform
      {
        "positionX" => 0,
        "positionY" => 0,
        "rotation" => 0,
        "scaleX" => 1,
        "scaleY" => 1,
        "boundsType" => "OBS_BOUNDS_STRETCH",
        "boundsAlignment" => 0,
        "boundsWidth" => WEB_WIDTH,
        "boundsHeight" => WEB_HEIGHT,
        "cropLeft" => 0,
        "cropRight" => 0,
        "cropTop" => 0,
        "cropBottom" => 0
      }
    end

    def input_settings
      {
        "url" => "#{external_base_url}/overlay",
        "width" => WEB_WIDTH,
        "height" => WEB_HEIGHT,
        "shutdown" => false,
        "fps" => 60
      }
    end
  end
end
