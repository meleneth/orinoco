# frozen_string_literal: true

require "digest"
require "json"
require "time"

module D2r
  class CharacterArchive
    def call(event, state)
      return unless event.type == "d2r.character.observed"
      payload = event.payload
      at = Time.iso8601(event.occurred_at)
      D2rCharacter.transaction do
        character = D2rCharacter.find_or_create_by!(name: payload.fetch("name"), character_class: payload.fetch("character_class")) do |record|
          record.first_seen_at = at
          record.last_seen_at = at
        end
        character.lock!
        run = D2rRun.find_by(game_id: state.dig("game", "id")) if state.dig("game", "id") && !state.dig("game", "ended_at")
        run.update!(d2r_character: character) if run && run.d2r_character_id.nil?
        data = payload.slice("level", "experience", "stats")
        fingerprint = Digest::SHA256.hexdigest(JSON.generate([character.id, at.utc.iso8601(6), data]))
        D2rCharacterObservation.find_or_create_by!(fingerprint: fingerprint) do |observation|
          observation.d2r_character = character
          observation.d2r_run = run
          observation.kind = "character_sheet"
          observation.observed_at = at
          observation.data = data
        end
        if at >= character.last_seen_at
          character.update!(data.except("stats").merge("stats" => character.stats.merge(data.fetch("stats", {})), "last_seen_at" => at))
        end
      end
    end
  end
end
