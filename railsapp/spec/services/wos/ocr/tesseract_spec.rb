# frozen_string_literal: true

require "spec_helper"
require "wos/ocr/tesseract"

RSpec.describe Wos::Ocr::Tesseract do
  it "reports whether the tesseract binary is available" do
    expect(described_class.new.available?).to eq(system("tesseract", "--version", out: File::NULL, err: File::NULL))
  end

  it "raises a clear error when the binary is missing" do
    ocr = described_class.new(binary: "definitely-missing-tesseract")

    expect { ocr.call("some-image.png") }.to raise_error(Wos::Ocr::Tesseract::MissingBinary, /definitely-missing-tesseract/)
  end
end
