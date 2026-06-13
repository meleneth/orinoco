# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwitchChatBridge::Message do
  describe "#[] and #[]=" do
    it "reads and writes message fields by key" do
      message = described_class.new(
        tags: { display_name: "Melen" },
        emotes: [],
        name: "meleneth",
        txt: "hello"
      )

      expect(message[:txt]).to eq("hello")

      message[:txt] = "hello world"

      expect(message.txt).to eq("hello world")
    end
  end
end
