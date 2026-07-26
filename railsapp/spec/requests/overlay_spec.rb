# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Overlay", type: :request do
  class OverlaySpecRedis
    def initialize(value = nil)
      @value = value
    end

    def get(_key)
      @value
    end
  end

  before do
    allow(Redis).to receive(:new).and_return(OverlaySpecRedis.new(state&.to_json))
  end

  let(:state) { nil }

  it "renders the canonical transparent overlay layer host" do
    get overlay_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include('data-overlay-root="default"')
    expect(response.body).to include('id="overlay_layer_toasts"')
    expect(response.body).to include('data-overlay-layer="toasts"')
    expect(response.body).to include('@keyframes overlay-toast')
    expect(response.body).to include('id="overlay_layer_wos_brain"')
    expect(response.body).to include('data-overlay-layer="wos_brain"')
    expect(response.body).to include("Waiting for WOSBrain")
  end

  context "with persisted WOS state" do
    let(:state) do
      {
        "recognition" => {
          "ruleset" => { "mode" => "base", "hidden_letters" => 0, "fake_letters" => 0 },
          "letters" => [ { "char" => "A" }, { "char" => "B" } ],
          "remaining_words" => [
            { "length" => 4, "total" => 12, "solved" => 0, "remaining" => 12 },
            { "length" => 5, "total" => 6, "solved" => 1, "remaining" => 5 }
          ],
          "solved_words" => [
            { "state" => "blank", "word_length" => 5, "filled_count" => 0, "correct_word" => nil, "player" => nil },
            { "state" => "solved", "word_length" => 4, "filled_count" => 4, "correct_word" => "ABLE", "player" => "chatuser" }
          ]
        },
        "recognized_at" => "2026-07-13T08:00:00Z"
      }
    end

    it "renders the latest WOSBrain projection on page load" do
      get overlay_path

      expect(response.body).to include("AB")
      expect(response.body).to include("base")
      expect(response.body).to include("2026-07-13T08:00:00Z")
      expect(response.body).to include("Words")
      expect(response.body).to include("12 x 4")
      expect(response.body).to include("5 x 5")
      expect(response.body).to include("ABLE")
      expect(response.body).to include("chatuser")
    end
  end
end
