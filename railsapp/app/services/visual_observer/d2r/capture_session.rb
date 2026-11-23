# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

require_relative "image_info"
require_relative "states"
require_relative "../calibration"

module VisualObserver
  module D2r
    class CaptureSession
      class Invalid < ArgumentError; end

      SCHEMA_VERSION = 1
      MAX_FRAMES = 20
      MAX_INTERVAL = 30.0

      def initialize(session_runner:, output_root:, clock: -> { Time.now.utc }, sleeper: ->(seconds) { sleep(seconds) })
        @session_runner = session_runner
        @output_root = Pathname(output_root)
        @clock = clock
        @sleeper = sleeper
      end

      def capture(state:, source_name:, frame_count: 3, interval: 1.0, labels: {}, confirmed: false, session_id: nil)
        created_directory = false
        state = state.to_s
        source_name = source_name.to_s.strip
        frame_count = Integer(frame_count)
        interval = Float(interval)
        validate!(state:, source_name:, frame_count:, interval:, confirmed:)

        started_at = @clock.call.utc
        session_id ||= "#{started_at.strftime('%Y%m%dT%H%M%SZ')}-#{state}-#{SecureRandom.hex(3)}"
        directory = @output_root.join(session_id)
        raise Invalid, "capture directory already exists: #{directory}" if directory.exist?

        FileUtils.mkdir_p(directory)
        created_directory = true
        manifest = nil
        @session_runner.run do |session|
          manifest = capture_with_session(
            session:, directory:, session_id:, state:, source_name:, frame_count:, interval:,
            labels:, started_at:
          )
        end
        File.write(directory.join("manifest.json"), JSON.pretty_generate(manifest) << "\n")
        directory.join("manifest.json")
      rescue StandardError
        FileUtils.rm_rf(directory) if created_directory && directory&.exist? && !directory.join("manifest.json").exist?
        raise
      end

      private

      def capture_with_session(session:, directory:, session_id:, state:, source_name:, frame_count:, interval:, labels:, started_at:)
        video = session.apply_request("requestType" => "GetVideoSettings", "requestData" => {})
        program = session.apply_request("requestType" => "GetCurrentProgramScene", "requestData" => {})
        active_scene = program["currentProgramSceneName"]
        item = find_source_item(session.fetch_inventory, active_scene, source_name)
        transform = item && session.apply_request(
          "requestType" => "GetSceneItemTransform",
          "requestData" => { "sceneName" => item.fetch("scene_name"), "sceneItemId" => item.fetch("scene_item_id") }
        ).fetch("sceneItemTransform")
        native_width = integer_dimension(transform, "sourceWidth")
        native_height = integer_dimension(transform, "sourceHeight")
        geometry = calibration_geometry(transform:, item:, source_name:, video:)

        frames = Array.new(frame_count) do |index|
          request_data = { "sourceName" => source_name, "imageFormat" => "png", "imageCompressionQuality" => -1 }
          request_data.merge!("imageWidth" => native_width, "imageHeight" => native_height) if native_width && native_height
          response = session.apply_request("requestType" => "GetSourceScreenshot", "requestData" => request_data)
          bytes = decode_image_data(response.fetch("imageData"))
          info = ImageInfo.read(bytes)
          filename = format("frame-%02d.png", index + 1)
          File.binwrite(directory.join(filename), bytes)
          captured_at = @clock.call.utc.iso8601(6)
          @sleeper.call(interval) if index + 1 < frame_count && interval.positive?
          {
            "path" => filename,
            "captured_at" => captured_at,
            "format" => info.fetch("format"),
            "width" => info.fetch("width"),
            "height" => info.fetch("height"),
            "sha256" => Digest::SHA256.hexdigest(bytes)
          }
        end

        {
          "schema_version" => SCHEMA_VERSION,
          "session_id" => session_id,
          "started_at" => started_at.iso8601(6),
          "expected_ui_state" => state,
          "manual_confirmation" => { "confirmed" => true, "provenance" => "user_confirmed_before_capture" },
          "labels" => labels.transform_keys(&:to_s).transform_values(&:to_s),
          "obs" => {
            "source_name" => source_name,
            "scene_name" => item&.fetch("scene_name", nil) || active_scene,
            "scene_item_id" => item&.fetch("scene_item_id", nil),
            "active_scene_name" => active_scene,
            "base_dimensions" => dimensions(video, "baseWidth", "baseHeight"),
            "output_dimensions" => dimensions(video, "outputWidth", "outputHeight"),
            "source_dimensions" => native_width && native_height ? { "width" => native_width, "height" => native_height } : nil,
            "scene_item_transform" => transform
          },
          "game_window_resolution" => nil,
          "calibration" => { "region_name" => nil, "geometry" => geometry },
          "frames" => frames
        }
      end

      def find_source_item(inventory, active_scene, source_name)
        items = inventory.fetch(:scene_items_by_scene, inventory["scene_items_by_scene"] || {})
        ordered_scenes = [ active_scene, *items.keys ].compact.uniq
        ordered_scenes.each do |scene_name|
          match = Array(items[scene_name]).find { |entry| (entry["sourceName"] || entry[:sourceName]) == source_name }
          next unless match

          return {
            "scene_name" => scene_name,
            "scene_item_id" => match["sceneItemId"] || match[:sceneItemId]
          }
        end
        nil
      end

      def decode_image_data(value)
        encoded = value.to_s.sub(/\Adata:image\/[a-zA-Z0-9.+-]+;base64,/, "")
        Base64.strict_decode64(encoded)
      rescue ArgumentError => e
        raise Invalid, "OBS returned invalid base64 image data: #{e.message}"
      end

      def integer_dimension(hash, key)
        return unless hash

        value = Integer(Float(hash[key]))
        value if value.positive?
      rescue ArgumentError, TypeError
        nil
      end

      def dimensions(hash, width_key, height_key)
        width = integer_dimension(hash, width_key)
        height = integer_dimension(hash, height_key)
        width && height ? { "width" => width, "height" => height } : nil
      end

      def calibration_geometry(transform:, item:, source_name:, video:)
        return unless transform && item

        Calibration.import(
          scene_name: item.fetch("scene_name"),
          scene_item_id: item.fetch("scene_item_id"),
          source_name:,
          transform:,
          reference_width: video.fetch("baseWidth"),
          reference_height: video.fetch("baseHeight")
        ).fetch("rect")
      end

      def validate!(state:, source_name:, frame_count:, interval:, confirmed:)
        raise Invalid, "unknown D2R state: #{state}" unless States::ALL.include?(state)
        raise Invalid, "source name is required" if source_name.empty?
        raise Invalid, "frame count must be between 1 and #{MAX_FRAMES}" unless (1..MAX_FRAMES).cover?(frame_count)
        raise Invalid, "interval must be between 0 and #{MAX_INTERVAL} seconds" unless interval.finite? && interval.between?(0, MAX_INTERVAL)
        raise Invalid, "capture requires explicit user confirmation" unless confirmed
      end
    end
  end
end
