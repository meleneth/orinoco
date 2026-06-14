# frozen_string_literal: true

require "rails_helper"

RSpec.describe Overlay::SafeTemplate do
  it "renders simple variables and dotted paths" do
    template = described_class.new("Hello {{viewer.name}} from {{viewer.city}}")

    expect(template.render(
      "viewer" => {
        "name" => "Mel",
        "city" => "Portland"
      }
    )).to eq("Hello Mel from Portland")
  end

  it "supports symbol and string keys" do
    template = described_class.new("Hello {{viewer.name}}")

    expect(template.render(
      viewer: {
        name: "Mel"
      }
    )).to eq("Hello Mel")
  end

  it "escapes HTML values" do
    template = described_class.new("Hello {{viewer.name}}")

    expect(template.render(
      "viewer" => {
        "name" => "<Mel>"
      }
    )).to eq("Hello &lt;Mel&gt;")
  end

  it "treats missing values as empty strings" do
    template = described_class.new("Hello {{viewer.name}}")

    expect(template.render({})).to eq("Hello ")
  end

  it "rejects invalid placeholders" do
    invalid_templates = [
      "{{foo()}}",
      "{{foo.bar[0]}}",
      "{{foo | raw}}",
      "{{system(\"rm -rf /\")}}",
      "{{foo;bar}}"
    ]

    invalid_templates.each do |value|
      template = described_class.new(value)

      expect(template).not_to be_valid
      expect(template.validation_errors.join(" ")).to include("invalid placeholder")
      expect { template.render({}) }.to raise_error(Overlay::InvalidTemplateError)
    end
  end

  it "leaves literal text alone" do
    template = described_class.new("<%= 1 + 1 %>")

    expect(template.render({})).to eq("<%= 1 + 1 %>")
  end
end
