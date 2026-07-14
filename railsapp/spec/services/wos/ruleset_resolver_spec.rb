# frozen_string_literal: true

require "spec_helper"
require "wos/ruleset_resolver"

RSpec.describe Wos::RulesetResolver do
  it "resolves auto mode to the base ruleset until screenshot-level detection exists" do
    ruleset = described_class.new(config: { "ruleset_mode" => "auto" }).call

    expect(ruleset.to_h).to eq(
      mode: "base",
      hidden_letters: 0,
      fake_letters: 0,
      shows_solved_words: true,
      requires_chat_correlation: false
    )
  end

  it "resolves manual hidden and fake mode" do
    ruleset = described_class.new(
      config: {
        "ruleset_mode" => "manual",
        "manual_ruleset" => "hidden_and_fake"
      }
    ).call

    expect(ruleset.to_h).to include(
      mode: "hidden_and_fake",
      hidden_letters: 1,
      fake_letters: 1,
      shows_solved_words: true,
      requires_chat_correlation: false
    )
  end

  it "resolves high difficulty chat correlation mode" do
    ruleset = described_class.new(
      config: {
        "ruleset_mode" => "manual",
        "manual_ruleset" => "chat_correlation"
      }
    ).call

    expect(ruleset.to_h).to include(
      mode: "chat_correlation",
      hidden_letters: 1,
      fake_letters: 1,
      shows_solved_words: false,
      requires_chat_correlation: true
    )
  end
end