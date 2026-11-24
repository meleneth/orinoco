# frozen_string_literal: true

require "digest"
require "json"
require "time"

module D2r
  class CharacterArchive
    def call(event, state)
      return unless %w[d2r.character.selected d2r.character.created d2r.character.observed d2r.level.changed].include?(event.type)
      payload = event.payload
      at = Time.iso8601(event.occurred_at)
      projected = state.fetch("character", {})
      identity_key = payload["identity_key"] || projected["identity_key"]
      return if identity_key.blank? || payload["name"].blank? || payload["character_class"].blank?

      D2rCharacter.transaction do
        character = D2rCharacter.find_or_create_by!(identity_key:) do |record|
          record.name = payload.fetch("name")
          record.character_class = payload.fetch("character_class")
          record.first_seen_at = at
          record.last_seen_at = at
        end
        character.lock!
        run = D2rRun.find_by(game_id: state.dig("game", "id")) if state.dig("game", "id") && !state.dig("game", "ended_at")
        run.update!(d2r_character: character) if run && run.d2r_character_id.nil?
        data = payload.slice(
          "level", "experience", "experience_next_level", "unspent_attribute_points", "stats",
          "ladder", "hardcore", "expansion", "season", "observed_created_at"
        )
        fingerprint = Digest::SHA256.hexdigest(JSON.generate([ character.id, at.utc.iso8601(6), data ]))
        D2rCharacterObservation.find_or_create_by!(fingerprint: fingerprint) do |observation|
          observation.d2r_character = character
          observation.d2r_run = run
          observation.kind = event.type.delete_prefix("d2r.character.").delete_prefix("d2r.")
          observation.observed_at = at
          observation.data = data
        end
        if at >= character.last_seen_at
          attributes = data.slice("level", "experience", "ladder", "hardcore", "expansion", "season")
          attributes["observed_created_at"] = Time.iso8601(data["observed_created_at"]) if data["observed_created_at"].present?
          attributes["stats"] = character.stats.merge(data.fetch("stats", {}))
          character.update!(attributes.merge("name" => payload.fetch("name"),
            "character_class" => payload.fetch("character_class"), "last_seen_at" => at))
        end
      end
    end
  end
end
