# frozen_string_literal: true

require "optparse"
require "fileutils"
require "json"
require "vips"

options = { output: "tmp/d2r-xp-calibration", rect: [0.0, 0.85, 1.0, 0.15], scale: 3 }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby script/extract_d2r_xp_bar.rb [options] [images or directories]"
  parser.on("--rect X,Y,W,H", Array, "Normalized source rectangle") { |values| options[:rect] = values.map { |v| Float(v) } }
  parser.on("--output DIR") { |value| options[:output] = value }
  parser.on("--scale N", Integer) { |value| options[:scale] = value }
end.parse!
x, y, w, h = options[:rect]
abort "Invalid normalized rectangle" unless options[:rect].size == 4 && [x, y, w, h].all?(&:finite?) &&
  x >= 0 && y >= 0 && w > 0 && h > 0 && x + w <= 1.000001 && y + h <= 1.000001
abort "Scale must be positive" unless options[:scale].positive?

inputs = ARGV.empty? ? %w[spec/fixtures/files/d2r tmp/d2r-captures] : ARGV
paths = inputs.flat_map do |input|
  if File.directory?(input)
    Dir.glob(File.join(input, "**", "*")).select { |path| File.file?(path) && path.match?(/\.(png|jpe?g)\z/i) }
  elsif File.file?(input)
    [input]
  else
    abort "Missing input: #{input}"
  end
end.uniq.sort
abort "No screenshots found" if paths.empty?
output = File.expand_path(options[:output])
FileUtils.mkdir_p(output)
records = paths.each_with_index.map do |path, index|
  image = Vips::Image.new_from_file(path, access: :random)
  left = (x * image.width).round.clamp(0, image.width - 1)
  top = (y * image.height).round.clamp(0, image.height - 1)
  right = ((x + w) * image.width).round.clamp(left + 1, image.width)
  bottom = ((y + h) * image.height).round.clamp(top + 1, image.height)
  crop = image.crop(left, top, right - left, bottom - top)
  stem = format("%04d-%s", index + 1, File.basename(path, File.extname(path)))
  raw = "#{stem}.png"
  preview = "#{stem}-zoom.png"
  crop.write_to_file(File.join(output, raw))
  crop.resize(options[:scale], kernel: :nearest).write_to_file(File.join(output, preview))
  { source: File.expand_path(path), width: image.width, height: image.height,
    pixel_rect: [left, top, right - left, bottom - top],
    normalized_rect: options[:rect], crop: raw, preview: preview }
end
File.write(File.join(output, "manifest.json"), JSON.pretty_generate(records))
puts "Extracted #{records.size} regions into #{output}"
