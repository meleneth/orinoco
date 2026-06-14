require "erb"

module Overlay
  class SafeTemplate
    PLACEHOLDER_REGEX = /\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)\s*\}\}/.freeze
    CAPTURED_PLACEHOLDER_REGEX = /\{\{\s*(.*?)\s*\}\}/m.freeze
    PATH_REGEX = /\A[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*\z/.freeze

    attr_reader :template

    def initialize(template)
      @template = template.to_s
    end

    def render(context = {})
      validate!

      template.gsub(PLACEHOLDER_REGEX) do
        resolved = resolve_path(context, Regexp.last_match(1))
        ERB::Util.html_escape(resolved.to_s)
      end
    end

    def valid?
      validation_errors.empty?
    end

    def validate!
      return true if valid?

      raise InvalidTemplateError, validation_errors.join(", ")
    end

    def validation_errors
      errors = []

      template.scan(CAPTURED_PLACEHOLDER_REGEX) do |match|
        placeholder = match.first.to_s.strip
        next if placeholder.match?(PATH_REGEX)

        errors << "invalid placeholder #{placeholder.inspect}"
      end

      errors.uniq
    end

    private

    def resolve_path(context, path)
      current = context

      path.split(".").each do |segment|
        current = fetch_segment(current, segment)
        break if current.nil?
      end

      current
    end

    def fetch_segment(value, segment)
      return nil if value.nil?
      return value[segment] if value.is_a?(Hash) && value.key?(segment)
      return value[segment.to_sym] if value.is_a?(Hash) && value.key?(segment.to_sym)

      nil
    end
  end
end
