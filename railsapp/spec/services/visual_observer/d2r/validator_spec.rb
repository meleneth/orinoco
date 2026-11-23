# frozen_string_literal: true

require "spec_helper"
require "digest"
require "json"
require "tmpdir"
require "zlib"
require "visual_observer/d2r/validator"

RSpec.describe VisualObserver::D2r::Validator do
  def png
    chunk = lambda { |type, data| [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    "\x89PNG\r\n\x1a\n".b +
      chunk.call("IHDR", [ 1, 1, 8, 2, 0, 0, 0 ].pack("N2C5")) +
      chunk.call("IDAT", Zlib.deflate("\0\0\0\0")) +
      chunk.call("IEND", "")
  end

  def write_capture(root, state: "gameplay_idle", hash: nil, path: "frame.png")
    directory = Pathname(root).join(state)
    directory.mkpath
    directory.join("frame.png").binwrite(png)
    manifest = {
      "schema_version" => 1,
      "expected_ui_state" => state,
      "manual_confirmation" => { "confirmed" => true },
      "frames" => [ {
        "path" => path, "format" => "png", "width" => 1, "height" => 1,
        "sha256" => hash || Digest::SHA256.hexdigest(png)
      } ]
    }
    directory.join("manifest.json").write(JSON.generate(manifest))
  end

  it "validates image structure, dimensions, hashes, state labels, and pair coverage" do
    Dir.mktmpdir do |root|
      write_capture(root)
      result = described_class.new.validate(root)

      expect(result).to be_valid
      expect(result.states).to eq([ "gameplay_idle" ])
      expect(result.warnings).to include(match(/area_banner: missing positive/))
    end
  end

  it "rejects hash mismatches, invalid states, and paths that escape the session" do
    Dir.mktmpdir do |root|
      write_capture(root, state: "invalid_state", hash: "bad", path: "../frame.png")
      result = described_class.new.validate(root, require_pairs: true)

      expect(result).not_to be_valid
      expect(result.errors).to include(match(/unknown state/), match(/path must stay/), match(/missing positive/))
    end
  end
end
