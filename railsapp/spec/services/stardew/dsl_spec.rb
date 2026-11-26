# frozen_string_literal: true

require_relative "../../../app/services/stardew/dsl"

RSpec.describe Stardew::Dsl::Compiler do
  subject(:compiler) { described_class.new(ruleset: "stardew-1.6") }

  def declare_run(compiler, &block)
    compiler.goal_set(:test, &block)
    compiler.run(:test) do
      starts spring(1)
      finishes winter(28)
      include_goals :test
    end
  end

  it "compiles the default profile deterministically and deeply freezes it" do
    root = File.expand_path("../../../config/stardew", __dir__)
    compiler.load_file(File.join(root, "goals/year_one.rb"))
    compiler.load_file(File.join(root, "runs/year_one_community_center.rb"))
    ir = compiler.compile(:year_one_community_center)
    expect(ir.fetch("goals").fetch("meet_villagers").fetch("target").fetch("type")).to eq("talk")
    expect(ir.fetch("run").fetch("required")).to eq(["community_center"])
    expect(ir.fetch("goals").fetch("red_cabbage").fetch("routes")).to be_frozen
    expect(described_class.digest(ir)).to eq(described_class.digest(compiler.compile(:year_one_community_center)))
  end

  it "rejects cycles" do
    declare_run(compiler) do
      goal(:a) { target :acquire, :wood; requires :b }
      goal(:b) { target :acquire, :stone; requires :a }
    end
    expect { compiler.compile(:test) }.to raise_error(Stardew::Dsl::Error, /cycle/)
  end

  it "rejects unresolved dependencies" do
    declare_run(compiler) { goal(:a) { target :acquire, :wood; requires :missing } }
    expect { compiler.compile(:test) }.to raise_error(Stardew::Dsl::Error, /unknown goal reference/)
  end

  it "rejects invalid dates" do
    expect do
      declare_run(compiler) { goal(:a) { target :acquire, :wood; deadline spring(29) } }
    end.to raise_error(Stardew::Dsl::Error, /invalid season/)
  end

  it "rejects duplicate goals" do
    expect do
      declare_run(compiler) do
        goal(:a) { target :acquire, :wood }
        goal(:a) { target :acquire, :stone }
      end
    end.to raise_error(Stardew::Dsl::Error, /duplicate goal/)
  end

  it "rejects nonpositive quantities" do
    expect do
      declare_run(compiler) { goal(:a) { target :acquire, :wood, quantity: 0 } }
    end.to raise_error(Stardew::Dsl::Error, /positive integer/)
  end
end
