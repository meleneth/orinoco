# frozen_string_literal: true

require "rails_helper"

RSpec.describe Diorama, type: :model do
  subject(:diorama) do
    described_class.new(
      slug: "orinoco.clip_show.default",
      name: "Default Clip Show",
      version: "0.1.0",
      visibility: "private"
    )
  end

  it "is valid with required attributes" do
    expect(diorama).to be_valid
  end

  it "requires slug, name, version, and visibility" do
    diorama.slug = nil
    diorama.name = nil
    diorama.version = nil
    diorama.visibility = nil

    expect(diorama).to be_invalid
    expect(diorama.errors[:slug]).to include("can't be blank")
    expect(diorama.errors[:name]).to include("can't be blank")
    expect(diorama.errors[:version]).to include("can't be blank")
    expect(diorama.errors[:visibility]).to include("can't be blank")
  end

  it "validates slug format" do
    diorama.slug = "Orinoco Clip Show"

    expect(diorama).to be_invalid
    expect(diorama.errors[:slug]).to include("is invalid")
  end

  it "validates slug uniqueness" do
    described_class.create!(
      slug: "orinoco.clip_show.default",
      name: "Default Clip Show",
      version: "0.1.0",
      visibility: "private"
    )

    expect(diorama).to be_invalid
    expect(diorama.errors[:slug]).to include("has already been taken")
  end
end
