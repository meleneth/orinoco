# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dioramas::JsonImporter do
  let!(:diorama) do
    Dioramas::Defaults::ClipShow.find_or_create!
  end

  it "imports an exported diorama under a new name" do
    exported = Dioramas::JsonExporter.new(diorama).to_json

    imported = described_class.call(exported, name: "Imported Clip Show")

    expect(imported.name).to eq("Imported Clip Show")
    expect(imported.slug).not_to eq(diorama.slug)
    expect(imported.nodes.count).to eq(diorama.nodes.count)
    expect(imported.edges.count).to eq(diorama.edges.count)
    expect(imported.nodes.find_by!(slug: "asset.clip_countdown_text_box").data).to include(
      "asset_type" => "overlay_text_box"
    )
  end

  it "rejects payloads that are not dioramas" do
    expect do
      described_class.call({ "type" => "clip" }.to_json)
    end.to raise_error(Dioramas::ImportError, /must be a diorama/)
  end
end
