# frozen_string_literal: true

module D2r
  class ProgressionSummary
    ACT_TOWNS = { "Rogue Encampment" => 1, "Lut Gholein" => 2, "Kurast Docks" => 3,
      "Pandemonium Fortress" => 4, "Harrogath" => 5 }.freeze

    def self.call(runs, now: Time.current)
      result = { game_seconds: 0.0, town_seconds: 0.0, outside_seconds: 0.0,
        activities: Hash.new(0.0), act_arrivals: {}, unknown_games: 0 }
      previous_end = nil
      runs.sort_by(&:started_at).each do |run|
        if previous_end && run.started_at >= previous_end
          result[:outside_seconds] += run.started_at - previous_end
        end
        # An open historical record is not proof of continuous gameplay.
        finish = run.ended_at
        unless finish
          result[:unknown_games] += 1
          previous_end = nil
          next
        end
        duration = [finish - run.started_at, 0].max
        result[:game_seconds] += duration
        result[:activities][run.run_kind || "unclassified"] += duration
        run.steps.each do |step|
          name = step["name"]
          result[:town_seconds] += step["seconds"].to_f if ACT_TOWNS.key?(name)
          act = ACT_TOWNS[name]
          if act && run.difficulty.present? && step["started_at"]
            key = "#{run.difficulty} Act #{act}"
            result[:act_arrivals][key] ||= step["started_at"]
          end
        end
        previous_end = finish
      end
      result
    end
  end
end
