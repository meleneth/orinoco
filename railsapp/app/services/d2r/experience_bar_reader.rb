# frozen_string_literal: true

require "vips"

module D2r
  # Calibrated against the 480x300 and 1920x1200 D2R HUD corpus.
  # The pale XP strip is above the action buttons, not the gold stamina bar.
  class ExperienceBarReader
    def call(path)
      image = Vips::Image.new_from_file(path.to_s, access: :random)
      return unless (1.58..1.62).cover?(image.width.to_f / image.height)
      return if image.bands < 3

      top = (image.height * 0.85).round
      hud = image.crop(0, top, image.width, image.height - top)
      hud = hud[0..2].resize(480.0 / hud.width, vscale: 45.0 / hud.height, kernel: :linear).cast("uchar")
      return unless hud.width == 480 && hud.height == 45

      pixels = hud.write_to_memory.unpack("C*")
      pixel = ->(x, y) { pixels.slice((y * 480 + x) * 3, 3) }
      # Exclude ornamental separators between the ten XP segments.
      columns = (0...10).flat_map { |segment| (136 + segment * 21..151 + segment * 21).to_a }
      # The bottom metal rail remains visible even when XP is zero.
      rail = columns.count do |x|
        r, g, b = pixel.call(x, 23)
        r.between?(32, 100) && (r - g).abs <= 18 && (g - b).abs <= 30
      end
      return if rail < columns.size * 0.75

      states = columns.map do |x|
        r, g, b = pixel.call(x, 21)
        if r >= 150 && g >= 135 && (r - g).abs <= 35 && r - b <= 100
          :filled
        elsif [r, g, b].max <= 45
          :empty
        else
          :unknown
        end
      end
      return if states.count(:unknown) > columns.size * 0.15
      known = states.reject { |state| state == :unknown }
      return if known.empty?
      # A real bar is a left-aligned prefix, not arbitrary bright HUD text.
      first_empty = known.index(:empty)
      return if first_empty && known.drop(first_empty).count(:filled) > 2

      known.count(:filled).to_f / known.size
    rescue Vips::Error, Errno::ENOENT
      nil
    end
  end
end
