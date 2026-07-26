# frozen_string_literal: true

require "rails_helper"

RSpec.describe TankGame::CommandParser do
  subject(:parser) { described_class.new(config: config) }

  let(:config) do
    {
      "trigger_command" => "!TankGame",
      "signup_command" => "!signup",
      "aim_command" => "!aim",
      "weapon_command" => "!weapon"
    }
  end

  it "parses TankGame chat commands" do
    expect(parser.parse("!TankGame")).to have_attributes(type: :start, args: {})
    expect(parser.parse("!signup")).to have_attributes(type: :signup, args: {})
    expect(parser.parse("!aim 33, 88")).to have_attributes(type: :aim, args: { "angle" => 33.0, "power" => 88.0 })
    expect(parser.parse("!weapon 3")).to have_attributes(type: :weapon, args: { "weapon" => 3 })
    expect(parser.parse("hello")).to be_nil
  end
end
