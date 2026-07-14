# frozen_string_literal: true

require_relative "ruleset"

module Wos
  class RulesetResolver
    DEFAULT_CONFIG = {
      "ruleset_mode" => "auto",
      "manual_ruleset" => Wos::Ruleset::DEFAULT_MODE
    }.freeze

    def initialize(config: nil)
      @config = normalize_config(config)
    end

    def call(image: nil, regions: nil, small_text_regions: [])
      mode = @config.fetch("ruleset_mode", "auto")

      case mode.to_s
      when "manual"
        Wos::Ruleset.for_mode(@config.fetch("manual_ruleset", Wos::Ruleset::DEFAULT_MODE))
      else
        auto_ruleset(image: image, regions: regions, small_text_regions: small_text_regions)
      end
    end

    private

    def auto_ruleset(image:, regions:, small_text_regions:)
      # Placeholder for OCR/level-derived rules. Keep the result explicit so downstream
      # processors can depend on a ruleset even before auto-detection is smart.
      Wos::Ruleset.for_mode(Wos::Ruleset::DEFAULT_MODE)
    end

    def normalize_config(config)
      source = config.respond_to?(:config) ? config.config : config
      DEFAULT_CONFIG.merge((source || {}).transform_keys(&:to_s))
    end
  end
end