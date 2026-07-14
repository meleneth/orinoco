# frozen_string_literal: true

require_relative "region"

module Wos
  class SmallTextSegmenter
    BRIGHT_THRESHOLD = 200
    DARK_THRESHOLD = 65
    MIN_COMPONENT_AREA = 18
    MAX_COMPONENT_AREA = 2_000
    MIN_COMPONENT_WIDTH = 3
    MIN_COMPONENT_HEIGHT = 5
    LINE_Y_TOLERANCE = 10
    LINE_GAP_TOLERANCE = 18

    SmallTextRegion = Data.define(:index, :source_region, :region, :state, :text, :player, :confidence, :metrics) do
      def to_h
        {
          index: index,
          source_region: source_region,
          region: region.to_h,
          state: state,
          text: text,
          player: player,
          confidence: confidence,
          metrics: metrics
        }
      end
    end

    def call(image:, regions:)
      regions.flat_map do |source_region, region|
        line_regions_for(image: image, source_region: source_region, region: region)
      end.each_with_index.map do |entry, index|
        SmallTextRegion.new(
          index: index,
          source_region: entry.fetch(:source_region),
          region: entry.fetch(:region),
          state: "visible_unread",
          text: nil,
          player: nil,
          confidence: entry.fetch(:confidence),
          metrics: entry.fetch(:metrics)
        )
      end
    end

    private

    def line_regions_for(image:, source_region:, region:)
      crop = region.crop(image)
      gray = grayscale(crop)
      boxes = component_boxes(gray)
      lines = group_into_lines(boxes)

      lines.map do |line|
        box = merged_box(line)
        {
          source_region: source_region,
          region: Wos::Region.new(
            name: :small_text_line,
            left: region.left + box.fetch(:left),
            top: region.top + box.fetch(:top),
            width: box.fetch(:width),
            height: box.fetch(:height)
          ),
          confidence: confidence_for(line),
          metrics: {
            component_count: line.length,
            component_boxes: line.map { |component| component.except(:pixels) }
          }
        }
      end
    end

    def grayscale(image)
      source = image.bands >= 3 ? image[0..2] : image
      source.colourspace("b-w")
    end

    def component_boxes(gray)
      data = gray.write_to_memory.unpack("C*")
      active = data.map { |value| value >= BRIGHT_THRESHOLD || value <= DARK_THRESHOLD }
      connected_boxes(active: active, width: gray.width, height: gray.height)
        .select { |box| text_component?(box) }
        .sort_by { |box| [box.fetch(:top), box.fetch(:left)] }
    end

    def connected_boxes(active:, width:, height:)
      seen = Array.new(active.length, false)
      boxes = []

      height.times do |y|
        width.times do |x|
          index = y * width + x
          next unless active[index] && !seen[index]

          boxes << flood_box(active: active, seen: seen, width: width, height: height, start_x: x, start_y: y)
        end
      end

      boxes
    end

    def flood_box(active:, seen:, width:, height:, start_x:, start_y:)
      queue = [[start_x, start_y]]
      seen[start_y * width + start_x] = true
      min_x = max_x = start_x
      min_y = max_y = start_y
      pixels = 0

      until queue.empty?
        x, y = queue.pop
        pixels += 1
        min_x = [min_x, x].min
        max_x = [max_x, x].max
        min_y = [min_y, y].min
        max_y = [max_y, y].max

        [[1, 0], [-1, 0], [0, 1], [0, -1]].each do |dx, dy|
          nx = x + dx
          ny = y + dy
          next if nx.negative? || ny.negative? || nx >= width || ny >= height

          next_index = ny * width + nx
          next unless active[next_index] && !seen[next_index]

          seen[next_index] = true
          queue << [nx, ny]
        end
      end

      {
        left: min_x,
        top: min_y,
        width: max_x - min_x + 1,
        height: max_y - min_y + 1,
        pixels: pixels
      }
    end

    def text_component?(box)
      box.fetch(:pixels).between?(MIN_COMPONENT_AREA, MAX_COMPONENT_AREA) &&
        box.fetch(:width) >= MIN_COMPONENT_WIDTH &&
        box.fetch(:height) >= MIN_COMPONENT_HEIGHT
    end

    def group_into_lines(boxes)
      rows = []

      boxes.each do |box|
        row = rows.find { |candidate| vertical_neighbors?(candidate, box) }
        if row
          row << box
        else
          rows << [box]
        end
      end

      rows.flat_map { |row| split_wide_gaps(row.sort_by { |box| box.fetch(:left) }) }
        .select { |line| line.length >= 2 }
    end

    def vertical_neighbors?(line, box)
      line_box = merged_box(line)
      center_delta = (center_y(line_box) - center_y(box)).abs
      center_delta <= LINE_Y_TOLERANCE || overlaps_vertically?(line_box, box)
    end

    def split_wide_gaps(row)
      lines = [[]]
      row.each do |box|
        current = lines.last
        if current.empty? || box.fetch(:left) - right_edge(current.last) <= LINE_GAP_TOLERANCE
          current << box
        else
          lines << [box]
        end
      end
      lines
    end

    def merged_box(boxes)
      left = boxes.map { |box| box.fetch(:left) }.min
      top = boxes.map { |box| box.fetch(:top) }.min
      right = boxes.map { |box| right_edge(box) }.max
      bottom = boxes.map { |box| bottom_edge(box) }.max

      {
        left: left,
        top: top,
        width: right - left + 1,
        height: bottom - top + 1
      }
    end

    def center_y(box)
      box.fetch(:top) + (box.fetch(:height) / 2.0)
    end

    def right_edge(box)
      box.fetch(:left) + box.fetch(:width) - 1
    end

    def bottom_edge(box)
      box.fetch(:top) + box.fetch(:height) - 1
    end

    def overlaps_vertically?(left, right)
      [left.fetch(:top), right.fetch(:top)].max <= [bottom_edge(left), bottom_edge(right)].min
    end

    def confidence_for(line)
      [[line.length / 8.0, 1.0].min, 0.0].max.round(3)
    end
  end
end
