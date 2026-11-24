# frozen_string_literal: true

require "rails_helper"
require "d2r/ground_label_reader"

RSpec.describe D2r::GroundLabelReader do
  it "revisits OCR word regions to confirm a gold unique label" do
    tsv = <<~TSV
      level	page_num	block_num	par_num	line_num	word_num	left	top	width	height	conf	text
      5	1	1	1	1	1	10	30	60	12	95	Harlequin
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

  it "rejects gold game chat instead of manufacturing unique drops" do
    tsv = <<~TSV
      level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
      5\t1\t1\t1\t1\t1\t10\t30\t35\t12\t95\t[Game]
      5\t1\t1\t1\t1\t2\t48\t30\t50\t12\t95\tHexeract
      5\t1\t1\t1\t1\t3\t101\t30\t30\t12\t95\tsays:
      5\t1\t1\t1\t1\t4\t134\t30\t8\t12\t95\tI
      5\t1\t1\t1\t1\t5\t145\t30\t20\t12\t95\tam
      5\t1\t1\t1\t1\t6\t168\t30\t80\t12\t95\toverburdened.
    TSV
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture2).and_return([ tsv, status ])

    Tempfile.create([ "gold-game-chat", ".png" ]) do |file|
      Vips::Image.black(300, 100).new_from_image([ 150, 120, 40 ]).write_to_file(file.path)

      expect(described_class.new.call(file.path)).to be_empty
    end
  end

  it "rejects fragmented dialogue lines produced by OCR" do
    reader = described_class.new

    [ "Hexeract says", ": carry anymore.", ": a key.",
      "readily to the call of anguish." ].each do |label|
      expect(reader.send(:chat_or_system_label?, label)).to be(true), label
    end
  end
  it "never interprets lower-left chat as a ground unique even without chat prefixes" do
    tsv = <<~TSV
      level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
      5\t1\t1\t1\t1\t1\t10\t65\t40\t12\t95\tHarlequin
    TSV
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture2).and_return([ tsv, status ])

    Tempfile.create([ "chat-no-prefix", ".png" ]) do |file|
      Vips::Image.black(100, 100).new_from_image([ 150, 120, 40 ]).write_to_file(file.path)
      expect(described_class.new.call(file.path)).to be_empty
    end
  end

  it "still recognizes candidate ground labels outside the excluded chat rectangle" do
    tsv = <<~TSV
      level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
      5\t1\t1\t1\t1\t1\t72\t65\t25\t12\t95\tHarlequin
    TSV
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture2).and_return([ tsv, status ])

    Tempfile.create([ "ground-right", ".png" ]) do |file|
      Vips::Image.black(100, 100).new_from_image([ 150, 120, 40 ]).write_to_file(file.path)
      expect(described_class.new.call(file.path)).to eq([
        { "kind" => "unique", "name" => "Harlequin", "confidence" => "candidate" }
      ])
    end
  end

end
