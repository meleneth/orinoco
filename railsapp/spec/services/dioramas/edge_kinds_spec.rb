# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::EdgeKinds do
  describe ".child_kind_for" do
    it "maps supported edge kinds to child kinds" do
      expect(described_class.child_kind_for("uses")).to eq("trigger")
      expect(described_class.child_kind_for("selects")).to eq("selector")
      expect(described_class.child_kind_for("guards")).to eq("condition")
      expect(described_class.child_kind_for("executes")).to eq("effect")
      expect(described_class.child_kind_for("provides")).to eq("asset")
      expect(described_class.child_kind_for("places")).to eq("placement")
      expect(described_class.child_kind_for("binds")).to eq("binding")
      expect(described_class.child_kind_for("falls_back_to")).to eq("fallback")
    end

    it "allows contains to create a rule under an affordance parent" do
      expect(described_class.child_kind_for("contains", parent_kind: "affordance")).to eq("rule")
      expect(described_class.child_kind_for("contains", parent_kind: "rule")).to be_nil
    end
  end

  describe ".creatable_outgoing_edge_kinds_for" do
    it "shows only relevant outgoing kinds for affordance nodes" do
      expect(described_class.creatable_outgoing_edge_kinds_for("affordance")).to eq([ "contains" ])
    end

    it "shows only the rule sidebar buckets for rule nodes" do
      expect(described_class.creatable_outgoing_edge_kinds_for("rule")).to eq([ "uses", "selects", "guards", "executes" ])
    end

    it "omits unrelated buckets for other node kinds" do
      expect(described_class.creatable_outgoing_edge_kinds_for("effect")).to eq([ "provides" ])
    end
  end

  describe ".add_label_for" do
    it "returns compact add labels" do
      expect(described_class.add_label_for("executes")).to eq("Add effect")
      expect(described_class.add_label_for("contains")).to eq("Add rule")
    end
  end
end
