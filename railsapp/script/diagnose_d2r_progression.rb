# frozen_string_literal: true

require "json"
require "vips"
require_relative "../app/services/d2r/fast_classifier"
require_relative "../app/services/d2r/character_sheet_reader"
require_relative "../app/services/d2r/character_menu_reader"
require_relative "../app/services/d2r/experience_bar_reader"

abort "Usage: bundle exec ruby script/diagnose_d2r_progression.rb SCREENSHOT [SCREENSHOT ...]" if ARGV.empty?
classifier = D2r::FastClassifier.new
sheet = D2r::CharacterSheetReader.new
menu = D2r::CharacterMenuReader.new
xp = D2r::ExperienceBarReader.new

ARGV.each do |path|
  image = Vips::Image.new_from_file(path, access: :random)
  # Compare native and the default observer resolution independently.
  [nil, 640].each do |width|
    require "tempfile"
    Tempfile.create(["d2r-diagnostic-", ".jpg"]) do |file|
      input = path
      if width
        image.resize(width.to_f / image.width).jpegsave(file.path, Q: 70)
        input = file.path
      end
      signals = classifier.call(input).to_h.fetch("signals")
      report = { path: path, width: width || image.width, signals: signals,
        xp_fill: xp.call(input), sheet_reading: sheet.call(input),
        menu_readings: %w[character_select game_creation].to_h { |screen| [screen, menu.call(input, screen: screen)] } }
      puts JSON.generate(report)
    end
  end
end
