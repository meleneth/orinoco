# frozen_string_literal: true

module D2r
  # Pure event-stream inference, independent of UI/manual run selection.
  # Stages are ordered; merely visiting Black Marsh does not prove Countess.
  class RunInference
    ROUTES = {
      "countess" => [
        %w[Black\ Marsh], %w[Forgotten\ Tower], %w[Tower\ Cellar\ Level\ 1],
        %w[Tower\ Cellar\ Level\ 2], %w[Tower\ Cellar\ Level\ 3],
        %w[Tower\ Cellar\ Level\ 4], %w[Tower\ Cellar\ Level\ 5]
      ],
      "andariel" => [
        %w[Catacombs\ Level\ 2 Catacombs\ Level\ 3 Catacombs\ Level\ 4]
      ],
      "mephisto" => [ [ "Durance of Hate Level 2", "Durance of Hate Level 3" ] ],
      "diablo" => [ [ "River of Flame", "Chaos Sanctuary" ] ],
      "baal" => [ [ "Worldstone Keep Level 2", "Worldstone Keep Level 3", "Throne of Destruction", "Worldstone Chamber" ] ],
      "cows" => [ [ "Moo Moo Farm" ] ],
      "tristram" => [["Tristram"]],
      "tombs" => [["Tal Rasha\u0027s Tomb"]],
      "pre_tristram" => [["Blood Moor", "Den of Evil", "Cold Plains", "Stony Field", "Dark Wood"]],
      "travincal" => [ [ "Travincal" ] ]
    }.freeze

    def observe(state, event)
      return unless state["game"] && !state.dig("game", "ended_at")
      if event.type == "d2r.loot.rune.sighted"
        return unless state.dig("run", "kind") == "countess"
        return unless state["area"] == "Tower Cellar Level 5"
        evidence = state["run"]["evidence"] ||= []
        token = "Rune sighted at Tower Cellar Level 5: #{event.payload["name"]}"
        evidence << token unless evidence.include?(token)
        state["run"]["confidence"] = 0.995
        return
      end
      return unless event.type == "d2r.area.changed"

      area = event.payload["area"].to_s
      return if area.empty?

      seen = state["visited_areas"] ||= []
      seen << area unless seen.last == area
      seen.shift while seen.size > 64

      candidate = candidate_for(seen)
      return unless candidate

      kind, confidence, evidence = candidate
      current = state["run"]
      return if current && current["confidence"].to_f >= confidence && current["kind"] == kind
      return if current && current["confidence"].to_f > confidence

      at = event.occurred_at
      if current && current["kind"] == kind
        current["confidence"] = confidence
        current["evidence"] = evidence
      else
        state["run"] = {
          "kind" => kind, "inferred" => true, "confidence" => confidence,
          "evidence" => evidence, "repeated" => state["previous_run_kind"] == kind,
          "previous_steps" => state["previous_run_kind"] == kind ? Array(state.dig("previous_run", "steps")) : [],
          "started_at" => state.dig("game", "started_at") || at,
          "step" => nil, "steps" => []
        }
      end
    end

    private

    def candidate_for(seen)
      matches = ROUTES.filter_map do |kind, groups|
        route = groups.flatten
        observed = seen.select { |area| route.include?(area) }.uniq
        next if observed.empty?

        # The distinctive dungeon is strong evidence; generic waypoint areas
        # are weak. Report the evidence instead of manufacturing certainty.
        confidence = case kind
        when "countess"
          if observed.include?("Tower Cellar Level 5")
            0.99
          elsif observed.any? { |a| a.start_with?("Tower Cellar") }
            0.90
          elsif observed.include?("Forgotten Tower")
            0.75
          else
            0.35
          end
        when "pre_tristram"
          observed.size >= 2 ? 0.80 : 0.70
        when "andariel"
          observed.include?("Catacombs Level 4") ? 0.98 : 0.65
        when "mephisto", "diablo", "baal"
          observed.size >= 2 ? 0.98 : 0.75
        else
          0.98
        end
        next if confidence < 0.7

        [ kind, confidence, observed ]
      end
      matches.max_by { |_, confidence, evidence| [ confidence, evidence.length ] }
    end
  end
end
