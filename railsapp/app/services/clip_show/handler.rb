# frozen_string_literal: true

module ClipShow
  class Handler
    def initialize(inventory:, config:)
      @inventory = inventory
      @config = config
    end

    def call(event, ctx)
      @inventory
        .placements_for_input_uuid(event.payload.fetch("inputUuid"))
        .select { |placement| enabled_for_scene?(placement.fetch("sceneName")) }
        .each do |placement|
          ctx.publish(
            "obs.command.requested",
            {
              "request" => {
                "requestType" => "SetSceneItemEnabled",
                "requestData" => {
                  "sceneName" => placement.fetch("sceneName"),
                  "sceneItemId" => placement.fetch("sceneItemId"),
                  "sceneItemEnabled" => false
                }
              }
            },
            source: "clip_show"
          )
        end
    end

    private

    def enabled_for_scene?(scene_name)
      @config.enabled_for_scene?(name: :clip_show, scene_name: scene_name)
    end
  end
end