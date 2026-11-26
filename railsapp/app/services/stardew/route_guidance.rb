# frozen_string_literal: true

module Stardew
  module RouteGuidance
    LANDMARKS = {
      "JoshHouse" => "1 River Road: George, Evelyn and Alex's house, immediately east of Pierre's, near the river.",
      "alexs_house" => "1 River Road: the house immediately east of Pierre's, near the river.",
      "alexs_house_exterior" => "Outside 1 River Road, immediately east of Pierre's.",
      "SeedShop" => "Pierre's General Store, north side of the town square.",
      "pierres_store" => "Pierre's General Store, north side of the town square.",
      "pierres_exterior" => "Outside Pierre's, on the north side of the town square.",
      "AnimalShop" => "Marnie's Ranch: enter Cindersap Forest south of the farm; the ranch is near the northern entrance.",
      "marnies_ranch" => "Marnie's Ranch: enter Cindersap Forest south of the farm; the ranch is near the northern entrance.",
      "LeahHouse" => "Leah's small cottage just south of Marnie's Ranch.",
      "leahs_cottage" => "Leah's small cottage just south of Marnie's Ranch.",
      "HaleyHouse" => "2 Willow Lane: Haley and Emily's house in the southwest residential area of town, east of Jodi's house.",
      "emilys_house" => "2 Willow Lane: Haley and Emily's house, east of Jodi's in southwest town.",
      "SamHouse" => "1 Willow Lane: Jodi and Sam's house in the southwest corner of town.",
      "jodis_house" => "1 Willow Lane: Jodi and Sam's house in the southwest corner of town.",
      "willow_lane" => "Southwest town, along the residential street between Jodi's and Haley's houses.",
      "Trailer" => "Pam and Penny's trailer on the east side of town, near the river.",
      "trailer" => "Pam and Penny's trailer on the east side of town, near the river.",
      "Saloon" => "Stardrop Saloon, directly south of Pierre's at the town square.",
      "saloon" => "Stardrop Saloon, directly south of Pierre's at the town square.",
      "Blacksmith" => "Clint's blacksmith shop, across the river on the east side of town, north of the museum.",
      "blacksmith" => "Clint's blacksmith shop, across the river on the east side of town, north of the museum.",
      "ScienceHouse" => "Robin's Carpenter's Shop in the Mountains: take the northern farm exit and follow the path east.",
      "carpenters_shop" => "Robin's Carpenter's Shop in the Mountains: take the northern farm exit and follow the path east.",
      "carpenters_exterior" => "Outside Robin's Carpenter's Shop in the Mountains.",
      "linus_tent" => "Linus's tent uphill north of Robin's Carpenter's Shop, near the mine path.",
      "Tent" => "Linus's tent uphill north of Robin's Carpenter's Shop.",
      "FishShop" => "Willy's Fish Shop on the beach pier, south of town.",
      "fish_shop_exterior" => "Outside Willy's Fish Shop on the beach pier, south of town.",
      "Beach" => "Beach, reached by the southern exit from town.",
      "beach" => "Beach, reached by the southern exit from town.",
      "beach_bridge" => "The bridge on the beach, east of Willy's pier.",
      "JojaMart" => "JojaMart across the river in northeast town.",
      "jojamart" => "JojaMart across the river in northeast town.",
      "joja_bridge" => "The river crossing toward JojaMart in northeast town.",
      "Town" => "Pelican Town, east of the farm via the bus stop.",
      "town_square" => "Central town square, between Pierre's and the saloon.",
      "west_town_square" => "West side of the central town square, near the clinic.",
      "Mountain" => "Mountain area north of town, east of the farm's northern exit.",
      "Forest" => "Cindersap Forest, south of the farm.",
      "Hospital" => "Harvey's clinic, immediately west of Pierre's.",
      "ManorHouse" => "Mayor's Manor, southeast of the town square near the river.",
      "ArchaeologyHouse" => "Museum and library, across the river southeast of town."
    }.freeze

    def self.describe(task, state)
      subject = task[:target]["subject"]
      planned = task[:target].dig("options", "location")
      npc = Array(state["npcs"]).find { |entry| entry["npc"].to_s.casecmp?(subject) } if %w[talk gift].include?(task[:target]["type"])
      location = npc && npc["location"] || planned
      return unless location

      landmark = LANDMARKS.fetch(location, location.gsub(/([a-z])([A-Z])/, '\\1 \\2').tr("_", " "))
      return landmark unless npc
      return "#{landmark} Currently observed at tile #{npc["x"]}, #{npc["y"]}." unless location == state["location"]

      dx = npc["x"].to_i - state["tile_x"].to_i
      dy = npc["y"].to_i - state["tile_y"].to_i
      steps = []
      steps << "#{dx.abs} tiles #{dx.positive? ? "east" : "west"}" unless dx.zero?
      steps << "#{dy.abs} tiles #{dy.positive? ? "south" : "north"}" unless dy.zero?
      steps.empty? ? "Right beside you." : "In your current area: #{steps.join(", ")} from you."
    end
  end
end
