# frozen_string_literal: true

require "thread"
require "active_support/core_ext/string/inflections"

module ObsBridge
  class ObswsSession
    EVENT_NAME_BY_TYPE = {
      "media_input_playback_ended" => :media_input_playback_ended
    }.freeze

    def initialize(req:, events:)
      @req = req
      @events = events
      @event_queue = Queue.new
      @subscribed_event_types = []
    end

    def subscribe!(event_types)
      @subscribed_event_types = Array(event_types).map { |event_type| normalize_event_type(event_type) }.uniq

      @subscribed_event_types.each do |event_type|
        event_name = EVENT_NAME_BY_TYPE.fetch(event_type) do
          raise ArgumentError, "unsupported OBS event type #{event_type.inspect}"
        end

        @events.on(event_name) do |event|
          @event_queue << build_event_payload(event_type, event)
        end
      end

      true
    end

    def poll_events(timeout:)
      first_event = pop_event(timeout: timeout)
      return [] unless first_event

      events = [first_event]

      loop do
        events << @event_queue.pop(true)
      rescue ThreadError
        return events
      end
    end

    def apply_request(request)
      request_type = request.fetch("requestType")
      request_data = request.fetch("requestData", {})

      case request_type
      when "CreateScene"
        @req.create_scene(
          request_data.fetch("sceneName")
        )
      when "CreateInput"
        @req.create_input(
          request_data.fetch("sceneName"),
          request_data.fetch("inputName"),
          request_data.fetch("inputKind"),
          request_data.fetch("inputSettings"),
          request_data.fetch("sceneItemEnabled", true)
        )
      when "SetInputSettings"
        @req.set_input_settings(
          request_data.fetch("inputName"),
          request_data.fetch("inputSettings"),
          request_data.fetch("overlay", true)
        )
      when "SetSceneItemEnabled"
        @req.set_scene_item_enabled(
          request_data.fetch("sceneName"),
          request_data.fetch("sceneItemId"),
          request_data.fetch("sceneItemEnabled")
        )
      when "SetInputAudioMonitorType"
        @req.set_input_audio_monitor_type(
          request_data.fetch("inputName"),
          request_data.fetch("monitorType")
        )
      when "SetSceneItemTransform"
        @req.set_scene_item_transform(
          request_data.fetch("sceneName"),
          request_data.fetch("sceneItemId"),
          request_data.fetch("sceneItemTransform")
        )
      when "GetSourceScreenshot"
        get_source_screenshot(request_data)
      else
        raise ArgumentError, "unsupported OBS request type #{request_type.inspect}"
      end
    end

    def fetch_inventory
      scenes = normalize_scenes(Array(@req.get_scene_list.scenes))

      scene_items_by_scene = scenes.each_with_object({}) do |scene, result|
        scene_name = scene.fetch("sceneName")
        response = @req.get_scene_item_list(scene_name)
        result[scene_name] = normalize_scene_items(Array(response.scene_items))
      end

      {
        scenes: scenes,
        scene_items_by_scene: scene_items_by_scene
      }
    end

    def pump_once(timeout:)
      sleep timeout
    end

    def close
      @events.close
    end

    private

    def pop_event(timeout:)
      deadline = monotonic_now + timeout

      loop do
        return @event_queue.pop(true)
      rescue ThreadError
        return nil if monotonic_now >= deadline

        sleep 0.01
      end
    end

    def build_event_payload(event_type, event)
      {
        "eventType" => camelize_event_type(event_type),
        "eventData" => event_data_hash(event)
      }
    end

    def event_data_hash(event)
      case event
      when Hash
        stringify_keys(event)
      else
        {
          "inputName" => try_call(event, :input_name),
          "inputUuid" => try_call(event, :input_uuid)
        }.compact
      end
    end

    def normalize_scenes(raw_scenes)
      raw_scenes.map do |scene|
        {
          "sceneName" => fetch_value(scene, :sceneName, "sceneName", :name, "name")
        }.compact
      end
    end

    def normalize_scene_items(raw_items)
      raw_items.map do |item|
        {
          "sceneItemId" => fetch_value(item, :sceneItemId, "sceneItemId", :id, "id"),
          "sourceName" => fetch_value(item, :sourceName, "sourceName", :inputName, "inputName", :name, "name"),
          "sourceUuid" => fetch_value(item, :sourceUuid, "sourceUuid", :inputUuid, "inputUuid", :sourceId, "sourceId"),
          "sceneItemEnabled" => fetch_value(item, :sceneItemEnabled, "sceneItemEnabled", :enabled, "enabled")
        }.compact
      end
    end

    def get_source_screenshot(request_data)
      active_scene_name = current_program_scene_name
      source_name = first_present(request_data["sourceName"], request_data["sceneName"], active_scene_name)
      image_format = request_data.fetch("imageFormat", "png")
      image_width = request_data.fetch("imageWidth", 1280)
      image_height = request_data.fetch("imageHeight", 720)
      image_compression_quality = request_data.fetch("imageCompressionQuality", -1)
      response = @req.get_source_screenshot(
        source_name,
        image_format,
        image_width,
        image_height,
        image_compression_quality
      )

      {
        "imageData" => fetch_value(response, :imageData, "imageData", :image_data, "image_data"),
        "imageFormat" => image_format,
        "sourceName" => source_name,
        "activeSceneName" => active_scene_name,
        "imageWidth" => image_width,
        "imageHeight" => image_height,
        "imageCompressionQuality" => image_compression_quality
      }.compact
    end

    def first_present(*values)
      values.find { |value| value.respond_to?(:empty?) ? !value.empty? : !value.nil? }
    end

    def current_program_scene_name
      response = @req.get_current_program_scene
      fetch_value(response, :currentProgramSceneName, "currentProgramSceneName", :current_program_scene_name, "current_program_scene_name")
    end
    def fetch_value(object, *keys)
      keys.each do |key|
        if object.respond_to?(:key?) && object.key?(key)
          return object[key]
        end

        return object.public_send(key) if object.respond_to?(key)
      end

      nil
    end

    def try_call(object, method_name)
      return nil unless object.respond_to?(method_name)

      object.public_send(method_name)
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_s] =
          case value
          when Hash
            stringify_keys(value)
          when Array
            value.map { |entry| entry.is_a?(Hash) ? stringify_keys(entry) : entry }
          else
            value
          end
      end
    end

    def normalize_event_type(event_type)
      event_type.to_s.underscore
    end

    def camelize_event_type(event_type)
      normalize_event_type(event_type).camelize
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
