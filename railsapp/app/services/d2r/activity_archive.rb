# frozen_string_literal: true

require "digest"
require "time"

module D2r
  # Materializes distinct activity spans from archived area visits. Town is
  # in-game time but is not assigned to a field activity.
  class ActivityArchive
    TOWNS = ["Rogue Encampment", "Lut Gholein", "Kurast Docks", "Pandemonium Fortress", "Harrogath"].freeze
    AREAS = {
      "pre_tristram" => ["Blood Moor", "Den of Evil", "Cold Plains", "Stony Field", "Dark Wood"],
      "tristram" => ["Tristram"],
      "tombs" => ["Canyon of the Magi", "Tal Rasha's Tomb"],
      "act_2_progression" => ["Rocky Waste", "Dry Hills", "Far Oasis", "Lost City", "Valley of Snakes", "Arcane Sanctuary", "Tal Rasha's Chamber", "Sewers Level 1", "Sewers Level 2", "Sewers Level 3"],
      "act_3_progression" => ["Spider Forest", "Great Marsh", "Flayer Jungle", "Lower Kurast", "Kurast Bazaar", "Upper Kurast"],
      "act_4_progression" => ["Outer Steppes", "Plains of Despair", "City of the Damned"],
      "act_5_progression" => ["Bloody Foothills", "Frigid Highlands"],
      "ancients" => ["Arreat Summit"]
    }.freeze

    def self.kind(area)
      return nil if TOWNS.include?(area)
      return "countess" if area == "Forgotten Tower" || area.start_with?("Tower Cellar Level ")
      AREAS.find { |_, areas| areas.include?(area) }&.first ||
        RunInference::ROUTES.find { |_, groups| groups.flatten.include?(area) }&.first ||
        "unclassified"
    end

    def call(run)
      spans = []
      visits = run.steps.filter_map do |step|
        next unless step["name"] && step["started_at"] && step["ended_at"]
        [step["name"], Time.iso8601(step["started_at"]), Time.iso8601(step["ended_at"])]
      end.sort_by { |_, from, _| from }
      visits.each do |area, from, to|
        next unless to > from
        activity = self.class.kind(area)
        if activity && spans.last && spans.last[:kind] == activity && spans.last[:ended_at] == from
          spans.last[:ended_at] = to
          spans.last[:evidence] |= [area]
        elsif activity
          spans << { kind: activity, started_at: from, ended_at: to, evidence: [area] }
        end
      end
      D2rActivity.transaction do
        keys = spans.map do |span|
          key = Digest::SHA256.hexdigest([run.game_id, span[:kind], span[:started_at].utc.iso8601(6)].join("|"))
          activity = run.d2r_activities.find_or_initialize_by(boundary_key: key)
          activity.update!(span.merge(d2r_character_id: run.d2r_character_id))
          key
        end
        run.d2r_activities.where.not(boundary_key: keys).delete_all
      end
    end
  end
end
