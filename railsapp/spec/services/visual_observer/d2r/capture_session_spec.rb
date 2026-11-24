# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "zlib"
require "visual_observer/d2r/capture_session"

RSpec.describe VisualObserver::D2r::CaptureSession do
  def png(width: 4, height: 3, color: "\0\0\0")
    chunk = lambda do |type, data|
      [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
    end
    rows = Array.new(height) { "\0" + (color * width) }.join
    "\x89PNG\r\n\x1a\n".b +
      chunk.call("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("N2C5")) +
      chunk.call("IDAT", Zlib.deflate(rows)) +
      chunk.call("IEND", "")
  end

  class FakeD2rRunner
    def initialize(session)
      @session = session
    end

    def run
      yield @session
    end
  end

  class FakeD2rSession
    attr_reader :screenshot_requests

    def initialize(image)
      @image = image
      @screenshot_requests = []
    end

    def fetch_inventory
      { scene_items_by_scene: { "Game" => [ { "sourceName" => "D2R", "sceneItemId" => 7 } ] } }
    end

    def apply_request(request)
      case request.fetch("requestType")
      when "GetVideoSettings"
        { "baseWidth" => 1920, "baseHeight" => 1080, "outputWidth" => 1280, "outputHeight" => 720 }
      when "GetCurrentProgramScene"
        { "currentProgramSceneName" => "Game" }
      when "GetSceneItemTransform"
        { "sceneItemTransform" => { "sourceWidth" => 4.0, "sourceHeight" => 3.0, "cropBottom" => 1 } }
      when "GetSourceScreenshot"
        @screenshot_requests << request.fetch("requestData")
        { "imageData" => "data:image/png;base64,#{Base64.strict_encode64(@image)}" }
      else
        raise "unexpected request"
      end
    end
  end

  it "captures bounded native-size frames with hashes and traceable OBS metadata" do
    Dir.mktmpdir do |root|
      session = FakeD2rSession.new(png)
      capture = described_class.new(
        session_runner: FakeD2rRunner.new(session), output_root: root,
        clock: -> { Time.utc(2026, 11, 22, 1, 2, 3) }, sleeper: ->(_seconds) { }
      )

      path = capture.capture(
        state: "gameplay_idle", source_name: "D2R", frame_count: 2, interval: 0,
        labels: { minimap: "open" }, confirmed: true, session_id: "fixture"
      )
      manifest = JSON.parse(path.read)

      expect(manifest.dig("obs", "source_dimensions")).to eq("width" => 4, "height" => 3)
      expect(manifest.dig("calibration", "geometry")).to eq(
        "x" => 0.0, "y" => 0.0, "width" => 1.0, "height" => (2.0 / 3)
      )
      expect(manifest.fetch("frames").map { |frame| frame.fetch("path") }).to eq(%w[frame-01.png frame-02.png])
      expect(manifest.dig("labels", "minimap")).to eq("open")
      expect(session.screenshot_requests).to all(include("imageWidth" => 4, "imageHeight" => 3))
    end
  end

  it "captures a Game Capture source when OBS reports unusable transform dimensions" do
    Dir.mktmpdir do |root|
      session = FakeD2rSession.new(png)
      allow(session).to receive(:apply_request).and_wrap_original do |original, request|
        if request.fetch("requestType") == "GetSceneItemTransform"
          { "sceneItemTransform" => { "sourceWidth" => 0.0, "sourceHeight" => 0.0 } }
        else
          original.call(request)
        end
      end
      capture = described_class.new(
        session_runner: FakeD2rRunner.new(session), output_root: root,
        sleeper: ->(_seconds) { }
      )

      path = capture.capture(
        state: "character_select", source_name: "D2R", frame_count: 1,
        interval: 0, confirmed: true
      )
      manifest = JSON.parse(path.read)

      expect(manifest.dig("obs", "source_dimensions")).to be_nil
      expect(manifest.dig("calibration", "geometry")).to be_nil
      expect(session.screenshot_requests).to contain_exactly(
        "sourceName" => "D2R", "imageFormat" => "png", "imageCompressionQuality" => -1
      )
    end
  end

  it "rejects unconfirmed captures and unsafe sampling bounds" do
    capture = described_class.new(session_runner: FakeD2rRunner.new(nil), output_root: "/unused")

    expect { capture.capture(state: "gameplay_idle", source_name: "D2R", confirmed: false) }
      .to raise_error(described_class::Invalid, /explicit user confirmation/)
    expect { capture.capture(state: "gameplay_idle", source_name: "D2R", frame_count: 21, confirmed: true) }
      .to raise_error(described_class::Invalid, /frame count/)
    expect { capture.capture(state: "made_up", source_name: "D2R", confirmed: true) }
      .to raise_error(described_class::Invalid, /unknown D2R state/)
  end


  it "never removes a pre-existing capture directory" do
    Dir.mktmpdir do |root|
      existing = Pathname(root).join("existing")
      existing.mkpath
      existing.join("keep.txt").write("user data")
      capture = described_class.new(session_runner: FakeD2rRunner.new(nil), output_root: root)

      expect do
        capture.capture(
          state: "gameplay_idle", source_name: "D2R", confirmed: true, session_id: "existing"
        )
      end.to raise_error(described_class::Invalid, /already exists/)
      expect(existing.join("keep.txt").read).to eq("user data")
    end
  end
end
