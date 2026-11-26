# frozen_string_literal: true

require_relative "../app/services/stardew/dsl"

root = File.expand_path("../config/stardew", __dir__)
compiler = Stardew::Dsl::Compiler.new(ruleset: "stardew-1.6")
Dir.glob(File.join(root, "goals/*.rb")).sort.each { |path| compiler.load_file(path) }
Dir.glob(File.join(root, "runs/*.rb")).sort.each { |path| compiler.load_file(path) }
ir = compiler.compile((ARGV.first || "year_one_community_center").to_sym)
puts Stardew::Dsl::Compiler.json(ir)
warn "revision: #{Stardew::Dsl::Compiler.digest(ir)}"
