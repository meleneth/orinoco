# frozen_string_literal: true

require "json"
require "optparse"

require_relative "capture_session"
require_relative "states"
require_relative "validator"

module VisualObserver
  module D2r
    class Cli
      def initialize(session_runner:, output_root:, input: $stdin, output: $stdout, error: $stderr)
        @session_runner = session_runner
        @output_root = output_root
        @input = input
        @output = output
        @error = error
      end

      def run(argv)
        command = argv.shift
        case command
        when "capture" then capture(argv)
        when "guide" then guide(argv)
        when "validate" then validate(argv)
        else
          @error.puts usage
          2
        end
      rescue OptionParser::ParseError, CaptureSession::Invalid, ArgumentError => e
        @error.puts "error: #{e.message}"
        2
      end

      private

      def capture(argv, confirmed: false)
        options = capture_options(argv)
        confirmed ||= options.delete(:confirmed)
        state = argv.shift or raise OptionParser::MissingArgument, "STATE"
        raise OptionParser::InvalidArgument, argv.join(" ") if argv.any?

        path = capturer.capture(state:, confirmed:, **options)
        @output.puts path
        0
      end

      def guide(argv)
        options = { source_name: nil, states: States::ALL, frame_count: 3, interval: 1.0, labels: {} }
        parser = OptionParser.new do |opts|
          opts.on("--source NAME") { |value| options[:source_name] = value }
          opts.on("--states LIST") { |value| options[:states] = value.split(",") }
          opts.on("--frames COUNT", Integer) { |value| options[:frame_count] = value }
          opts.on("--interval SECONDS", Float) { |value| options[:interval] = value }
        end
        parser.parse!(argv)
        raise OptionParser::MissingArgument, "--source NAME" if options[:source_name].to_s.empty?
        unknown = options[:states] - States::ALL
        raise OptionParser::InvalidArgument, "unknown states: #{unknown.join(', ')}" if unknown.any?

        options.delete(:states).each do |state|
          @output.puts "\n#{state}: #{States::PROMPTS.fetch(state)}"
          @output.print "Press Enter to capture, s to mark missing, or q to stop: "
          @output.flush
          answer = @input.gets&.strip&.downcase
          break if answer == "q" || answer.nil?
          next if answer == "s"

          path = capturer.capture(state:, confirmed: true, **options)
          @output.puts "Captured #{path}"
        end
        0
      end

      def validate(argv)
        require_pairs = false
        parser = OptionParser.new { |opts| opts.on("--require-pairs") { require_pairs = true } }
        parser.parse!(argv)
        path = argv.shift || @output_root
        raise OptionParser::InvalidArgument, argv.join(" ") if argv.any?

        result = Validator.new.validate(path, require_pairs:)
        @output.puts JSON.pretty_generate(result.to_h)
        result.valid? ? 0 : 1
      end

      def capture_options(argv)
        options = { source_name: nil, frame_count: 3, interval: 1.0, labels: {}, confirmed: false }
        parser = OptionParser.new do |opts|
          opts.on("--source NAME") { |value| options[:source_name] = value }
          opts.on("--frames COUNT", Integer) { |value| options[:frame_count] = value }
          opts.on("--interval SECONDS", Float) { |value| options[:interval] = value }
          opts.on("--label KEY=VALUE") do |value|
            key, label = value.split("=", 2)
            raise OptionParser::InvalidArgument, "label must be KEY=VALUE" if key.to_s.empty? || label.nil?
            options[:labels][key] = label
          end
          opts.on("--confirmed") { options[:confirmed] = true }
        end
        parser.parse!(argv)
        raise OptionParser::MissingArgument, "--source NAME" if options[:source_name].to_s.empty?
        options
      end

      def capturer
        @capturer ||= CaptureSession.new(session_runner: @session_runner, output_root: @output_root)
      end

      def usage
        <<~TEXT
          Usage:
            d2r_capture capture STATE --source NAME --confirmed [--frames N] [--interval SECONDS] [--label KEY=VALUE]
            d2r_capture guide --source NAME [--states STATE,...] [--frames N] [--interval SECONDS]
            d2r_capture validate [PATH] [--require-pairs]
        TEXT
      end
    end
  end
end
