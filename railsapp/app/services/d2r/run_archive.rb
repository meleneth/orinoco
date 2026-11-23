# frozen_string_literal: true

require "digest"
require "json"
require "time"

module D2r
  # Durable history fed by the SAME detector event stream as the live Redis
  # projection. The game_id is a natural key for SQS redelivery/idempotency.
  class RunArchive
    EVENT_LIMIT = 1000

    def call(event, state)
      game = state["game"]
      return unless game && game["id"].present?

      game_id = game.fetch("id")
      at = Time.iso8601(event.occurred_at)
      # The live projection never invents an in-game ID from area chatter.
      return if event.type == "d2r.game.started" && event.payload["game_id"] != game_id

      D2rRun.transaction do
        run = D2rRun.find_or_create_by!(game_id: game_id) do |record|
          record.started_at = Time.iso8601(game.fetch("started_at"))
        end
        run.lock!
        # A repeated SQS delivery must never rewrite a finished run or
        # roll the archive backwards when old events arrive late.
        return run if run.last_event_at && at < run.last_event_at
        return run if run.ended_at && event.type != "d2r.game.ended"

        changes = {
          started_at: Time.iso8601(game.fetch("started_at")),
          run_started_at: parse_time(state.dig("run", "started_at")),
          run_kind: state.dig("run", "kind"),
          repeated: !!state.dig("run", "repeated"),
          character_level: state["level"],
          area: state["area"],
          difficulty: state["difficulty"],
          screen: state["screen"],
          terror_zones: state["terror_zones"] || [],
          steps: state.dig("run", "steps") || [],
          current_step: state.dig("run", "step") || {},
          last_event_at: at
        }
        changes[:ended_at] = Time.iso8601(game.fetch("ended_at")) if game["ended_at"]

        unless %w[d2r.state.changed d2r.loading.started d2r.loading.finished].include?(event.type)
          entry = { "type" => event.type, "at" => at.utc.iso8601(6),
                    "payload" => event.payload.except("screenshot", "classification") }
          # A content fingerprint makes deliveries idempotent even across retries.
          entry["id"] = Digest::SHA256.hexdigest(JSON.generate(entry))
          existing = run.events
          changes[:events] = (existing.any? { |old| old["id"] == entry["id"] } ?
            existing : (existing + [entry]).last(EVENT_LIMIT))
        end
        run.update!(changes)
        run
      end
    end

    private

    def parse_time(value)
      Time.iso8601(value) if value
    end
  end
end
