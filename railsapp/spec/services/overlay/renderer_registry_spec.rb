# frozen_string_literal: true

require "rails_helper"

RSpec.describe Overlay::RendererRegistry do
  it "resolves known renderers without constantizing" do
    expect(described_class.fetch!("text_box")).to eq(Overlay::Renderers::TextBox)
    expect(described_class.fetch!("timer_text")).to eq(Overlay::Renderers::TimerText)
    expect(described_class.known?("text_box")).to eq(true)
    expect(described_class.keys).to match_array(%w[text_box timer_text])
  end

  it "rejects unknown renderer keys" do
    expect { described_class.fetch!("Kernel") }.to raise_error(Overlay::UnknownRendererError)
    expect(described_class.known?("Kernel")).to eq(false)
  end
end
