# frozen_string_literal: true

require "vips"

module D2r
  class FastFingerprint
    HASH_COLUMNS = 16
    HASH_ROWS = 10
    SAMPLE_COLUMNS = HASH_COLUMNS + 1

    ROIS = {
      "full" => [ 0.0, 0.0, 1.0, 1.0 ],
      "game_hud" => [ 0.0, 0.88, 1.0, 0.12 ],
      "left_panel" => [ 0.0, 0.0, 0.43, 0.82 ],
      "right_panel" => [ 0.57, 0.0, 0.43, 0.82 ],
      "tooltip_zone" => [ 0.0, 0.16, 0.94, 0.55 ]
    }.freeze

    def call(path)
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      ROIS.transform_values { |rect| fingerprint(crop(image, rect)) }
    end

    def distance(first, second)
      differing_bits = (Integer(first, 16) ^ Integer(second, 16)).to_s(2).count("1")
      differing_bits.to_f / (HASH_COLUMNS * HASH_ROWS)
    end

    private

    def crop(image, rect)
      x = (rect.fetch(0) * image.width).round.clamp(0, image.width - 1)
      y = (rect.fetch(1) * image.height).round.clamp(0, image.height - 1)
      width = (rect.fetch(2) * image.width).round.clamp(1, image.width - x)
      height = (rect.fetch(3) * image.height).round.clamp(1, image.height - y)
      image.crop(x, y, width, height)
    end

    def fingerprint(image)
      gray = image.bands >= 3 ? image[0..2].colourspace("b-w") : image
      sample = gray.thumbnail_image(SAMPLE_COLUMNS, height: HASH_ROWS, size: :force)
      pixels = sample.write_to_memory.unpack("C*")
      bits = HASH_ROWS.times.flat_map do |row|
        HASH_COLUMNS.times.map do |column|
          offset = (row * SAMPLE_COLUMNS) + column
          pixels.fetch(offset) <= pixels.fetch(offset + 1) ? 1 : 0
        end
      end
      bits.each_slice(4).map { |nibble| nibble.join.to_i(2).to_s(16) }.join
    end
  end
end
