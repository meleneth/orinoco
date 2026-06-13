# frozen_string_literal: true

require "rails_helper"

RSpec.describe DioramaImageValue do
  describe "#valid?" do
    it "accepts valid inline SVG values" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/svg+xml",
        "encoding" => "utf8",
        "data" => "<svg xmlns='http://www.w3.org/2000/svg'></svg>",
        "sha256" => "abc123",
        "byte_size" => 64,
        "width" => 16,
        "height" => 16
      )

      expect(value).to be_valid
    end

    it "accepts valid inline PNG base64 values" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/png",
        "encoding" => "base64",
        "data" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB",
        "sha256" => "def456",
        "byte_size" => 32,
        "width" => 1,
        "height" => 1
      )

      expect(value).to be_valid
    end

    it "rejects missing data for inline storage" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/png",
        "encoding" => "base64",
        "sha256" => "def456",
        "byte_size" => 32
      )

      expect(value).not_to be_valid
      expect(value.validation_errors).to include("data is required for inline storage")
    end

    it "rejects missing asset_ref for asset_ref storage" do
      value = described_class.new(
        "storage" => "asset_ref",
        "media_type" => "image/png",
        "sha256" => "def456",
        "byte_size" => 32
      )

      expect(value).not_to be_valid
      expect(value.validation_errors).to include("asset_ref is required for asset_ref storage")
    end

    it "rejects SVG inline values with base64 encoding" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/svg+xml",
        "encoding" => "base64",
        "data" => "PHN2Zz48L3N2Zz4=",
        "sha256" => "ghi789",
        "byte_size" => 16
      )

      expect(value).not_to be_valid
      expect(value.validation_errors).to include("inline SVG must use utf8 encoding")
    end

    it "rejects raster inline values with utf8 encoding" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/png",
        "encoding" => "utf8",
        "data" => "not-base64",
        "sha256" => "ghi789",
        "byte_size" => 16
      )

      expect(value).not_to be_valid
      expect(value.validation_errors).to include("inline raster images must use base64 encoding")
    end

    it "rejects unsupported media types" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/bmp",
        "encoding" => "base64",
        "data" => "AAA",
        "sha256" => "ghi789",
        "byte_size" => 16
      )

      expect(value).not_to be_valid
      expect(value.validation_errors.join(" ")).to include("media_type must be one of")
    end

    it "rejects oversized inline images" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/png",
        "encoding" => "base64",
        "data" => "AAA",
        "sha256" => "ghi789",
        "byte_size" => (256 * 1024) + 1
      )

      expect(value).not_to be_valid
      expect(value.validation_errors.join(" ")).to include("maximum size")
    end
  end

  describe "#data_url" do
    it "builds an escaped SVG data URL" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/svg+xml",
        "encoding" => "utf8",
        "data" => "<svg xmlns='http://www.w3.org/2000/svg'></svg>",
        "sha256" => "abc123",
        "byte_size" => 64
      )

      expect(value.data_url).to start_with("data:image/svg+xml;utf8,")
      expect(value.data_url).to include("%3Csvg")
    end

    it "builds a base64 raster data URL" do
      value = described_class.new(
        "storage" => "inline",
        "media_type" => "image/png",
        "encoding" => "base64",
        "data" => "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB",
        "sha256" => "def456",
        "byte_size" => 32
      )

      expect(value.data_url).to eq("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB")
    end
  end
end
