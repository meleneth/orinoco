# frozen_string_literal: true

module TankGame
  class CommandParser
    Command = Data.define(:type, :args)

    def initialize(config:)
      @config = config
    end

    def parse(text)
      body = text.to_s.strip
      return nil if body.empty?

      if command_match?(body, trigger_command)
        Command.new(type: :start, args: {})
      elsif command_match?(body, demo_command)
        Command.new(type: :demo, args: {})
      elsif command_match?(body, signup_command)
        Command.new(type: :signup, args: {})
      elsif (match = body.match(/\A#{Regexp.escape(aim_command)}\s+(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\z/i))
        Command.new(type: :aim, args: { "angle" => match[1].to_f, "power" => match[2].to_f })
      elsif (match = body.match(/\A#{Regexp.escape(weapon_command)}\s+(\d+)\s*\z/i))
        Command.new(type: :weapon, args: { "weapon" => match[1].to_i })
      end
    end

    private

    attr_reader :config

    def command_match?(body, command)
      body.casecmp?(command)
    end

    def trigger_command
      config.fetch("trigger_command", "!TankGame")
    end

    def demo_command
      config.fetch("demo_command", "!TankDemo")
    end

    def signup_command
      config.fetch("signup_command", "!signup")
    end

    def aim_command
      config.fetch("aim_command", "!aim")
    end

    def weapon_command
      config.fetch("weapon_command", "!weapon")
    end
  end
end
