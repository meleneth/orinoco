# frozen_string_literal: true

require "digest"
require "json"
require "time"

module D2r
  class DropArchive
    GAME = {
      name: "Diablo II: Resurrected",
      publisher: "Blizzard Entertainment",
      year: 2021,
      link: "https://diablo2.blizzard.com/"
    }.freeze
    DEFAULT_SEASON_NAME = "Season 1"

    def call(event, run:)
      at = Time.iso8601(event.occurred_at)
      payload = event.payload.except("screenshot", "classification")
      fingerprint = Digest::SHA256.hexdigest(JSON.generate({
        "game_id" => run.game_id,
        "type" => event.type,
        "at" => at.utc.iso8601(6),
        "payload" => payload
      }))

      LootDrop.find_or_create_by!(event_fingerprint: fingerprint) do |drop|
        drop.season = current_season!
        drop.d2r_run = run
        drop.kind = event.type == "d2r.loot.rune.sighted" ? "rune" : "unique"
        drop.name = event.payload.fetch("name")
        drop.confidence = event.payload["confidence"] || "candidate"
        drop.observed_at = at
        drop.metadata = payload.except("name", "confidence")
      end
    end

    private

    def current_season!
      game = GameDefinition.find_or_create_by!(GAME.slice(:name, :publisher, :year)) do |definition|
        definition.link = GAME.fetch(:link)
      end
      game.seasons.find_by(active: true) || game.seasons.create!(
        name: ENV.fetch("D2R_SEASON_NAME", DEFAULT_SEASON_NAME),
        active: true
      )
    end
  end
end
