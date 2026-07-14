# frozen_string_literal: true

require "fileutils"
require "json"

module Wos
  class DebugExporter
    def initialize(output_dir:)
      @output_dir = output_dir.to_s
    end

    def export!(image:, result:)
      FileUtils.mkdir_p(@output_dir)
      result.regions.each do |name, region|
        path = File.join(@output_dir, "#{name}.png")
        region.crop(image).write_to_file(path)
      end
      export_letter_tiles!(image: image, result: result)
      export_small_text!(image: image, result: result)
      File.write(File.join(@output_dir, "recognition.json"), JSON.pretty_generate(result.to_h))
      result
    end
    private

    def export_small_text!(image:, result:)
      text_dir = File.join(@output_dir, "small_text")
      FileUtils.rm_rf(text_dir)
      FileUtils.mkdir_p(text_dir)
      result.small_text_regions.each do |entry|
        path = File.join(
          text_dir,
          "text_#{entry.index.to_s.rjust(2, "0")}_#{entry.source_region}.png"
        )
        entry.region.crop(image).write_to_file(path)
      end
    end
    def export_letter_tiles!(image:, result:)
      tile_dir = File.join(@output_dir, "letter_tiles")
      FileUtils.rm_rf(tile_dir)
      FileUtils.mkdir_p(tile_dir)
      result.letter_tiles.each do |tile|
        suffix = [tile.state, tile.char].compact.join("_")
        path = File.join(tile_dir, "tile_#{tile.index.to_s.rjust(2, "0")}_#{suffix}.png")
        tile.region.crop(image).write_to_file(path)
      end
    end
  end
end
