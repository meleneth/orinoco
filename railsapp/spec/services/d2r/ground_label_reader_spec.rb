# frozen_string_literal: true

require "rails_helper"
require "d2r/ground_label_reader"

RSpec.describe D2r::GroundLabelReader do
  it "revisits OCR word regions to confirm a gold unique label" do
    tsv = <<~TSV
      level	page_num	block_num	par_num	line_num	word_num	left	top	width	height	conf	text
      5	1	1	1	1	1	10	10	60	12	95	Harlequin
    TSV
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture2).and_return([ tsv, status ])

    Tempfile.create([ "gold-ground-label", ".png" ]) do |file|
      Vips::Image.black(100, 100).new_from_image([ 150, 120, 40 ]).write_to_file(file.path)

      expect(described_class.new.call(file.path)).to eq([
        { "kind" => "unique", "name" => "Harlequin", "confidence" => "candidate" }
      ])
    end
  end
end
