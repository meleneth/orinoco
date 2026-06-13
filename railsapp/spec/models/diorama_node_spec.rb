# frozen_string_literal: true

require "rails_helper"

RSpec.describe DioramaNode, type: :model do
  let(:diorama) do
    Diorama.create!(
      slug: "orinoco.clip_show.default",
      name: "Default Clip Show",
      version: "0.1.0",
      visibility: "private"
    )
  end

  subject(:node) do
    described_class.new(
      diorama: diorama,
      slug: "rule.hide_clip_when_playback_ends",
      kind: "rule",
      name: "Hide Clip When Playback Ends"
    )
  end

  it "is valid with required attributes" do
    expect(node).to be_valid
  end

  it "requires slug, kind, and name" do
    node.slug = nil
    node.kind = nil
    node.name = nil

    expect(node).to be_invalid
    expect(node.errors[:slug]).to include("can't be blank")
    expect(node.errors[:kind]).to include("can't be blank")
    expect(node.errors[:name]).to include("can't be blank")
  end

  it "validates slug format" do
    node.slug = "Rule Hide Clip"

    expect(node).to be_invalid
    expect(node.errors[:slug]).to include("is invalid")
  end

  it "validates kind inclusion" do
    node.kind = "workflow"

    expect(node).to be_invalid
    expect(node.errors[:kind]).to include("is not included in the list")
  end

  it "validates slug uniqueness scoped to diorama" do
    described_class.create!(
      diorama: diorama,
      slug: "rule.hide_clip_when_playback_ends",
      kind: "rule",
      name: "Existing Rule"
    )

    expect(node).to be_invalid
    expect(node.errors[:slug]).to include("has already been taken")
  end

  it "allows the same slug in a different diorama" do
    other_diorama = Diorama.create!(
      slug: "orinoco.clip_show.experimental",
      name: "Experimental Clip Show",
      version: "0.1.0",
      visibility: "private"
    )

    described_class.create!(
      diorama: diorama,
      slug: "rule.hide_clip_when_playback_ends",
      kind: "rule",
      name: "Existing Rule"
    )

    other_node = described_class.new(
      diorama: other_diorama,
      slug: "rule.hide_clip_when_playback_ends",
      kind: "rule",
      name: "Rule In Other Diorama"
    )

    expect(other_node).to be_valid
  end
end
