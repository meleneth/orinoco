# frozen_string_literal: true

require "yaml"

truth_path = Rails.root.join("spec/fixtures/files/d2r/truth.yml")
truth = YAML.safe_load_file(truth_path)
classifier = D2r::FastClassifier.new
samples = truth.fetch("fixtures").select { |fixture| fixture.fetch("split") == "holdout" }.map do |fixture|
  result = classifier.call(truth_path.dirname.join(fixture.fetch("file")))
  expected = fixture.fetch("signals")
  actual = result.signals.transform_values { |signal| signal.fetch("state") }
  {
    "file" => fixture.fetch("file"),
    "correct" => expected == actual,
    "expected" => expected,
    "actual" => actual,
    "elapsed_ms" => result.elapsed_ms
  }
end

times = samples.map { |sample| sample.fetch("elapsed_ms") }.sort
summary = {
  "samples" => samples.size,
  "correct" => samples.count { |sample| sample.fetch("correct") },
  "median_ms" => times.fetch(times.size / 2),
  "p95_ms" => times.fetch([ (times.size * 0.95).ceil - 1, times.size - 1 ].min),
  "results" => samples
}
puts JSON.pretty_generate(summary)
exit 1 unless summary.fetch("correct") == summary.fetch("samples")
