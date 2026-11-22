# frozen_string_literal: true

require "yaml"
require_relative "../app/services/d2r/fast_classifier_trainer"

truth_path = Rails.root.join("spec/fixtures/files/d2r/truth.yml")
model = D2r::FastClassifierTrainer.new.train(truth_path: truth_path)
output_path = Rails.root.join("config/d2r_fast_classifier.yml")
File.write(output_path, YAML.dump(model))
puts output_path
