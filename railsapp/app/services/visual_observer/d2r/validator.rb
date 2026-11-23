# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

require_relative "image_info"
require_relative "states"

module VisualObserver
  module D2r
    class Validator
      Result = Struct.new(:errors, :warnings, :manifests, :states, keyword_init: true) do
        def valid?
          errors.empty?
        end

        def to_h
          { "valid" => valid?, "errors" => errors, "warnings" => warnings, "manifests" => manifests, "states" => states }
        end
      end

      def validate(path, require_pairs: false)
        root = Pathname(path).expand_path
        manifest_paths = root.file? ? [ root ] : Dir[root.join("**/manifest.json")].sort.map { |entry| Pathname(entry) }
        errors = []
        warnings = []
        states = []
        hashes = {}
        errors << "no manifests found under #{root}" if manifest_paths.empty?

        manifest_paths.each do |manifest_path|
          validate_manifest(manifest_path, errors:, warnings:, states:, hashes:)
        rescue JSON::ParserError => e
          errors << "#{manifest_path}: invalid JSON: #{e.message}"
        rescue Errno::ENOENT => e
          errors << "#{manifest_path}: #{e.message}"
        end
        validate_pairs(states.uniq, errors:, warnings:, required: require_pairs)

        Result.new(
          errors:, warnings:, manifests: manifest_paths.map(&:to_s), states: states.uniq.sort
        )
      end

      private

      def validate_manifest(manifest_path, errors:, warnings:, states:, hashes:)
        manifest = JSON.parse(manifest_path.read)
        prefix = manifest_path.to_s
        errors << "#{prefix}: unsupported schema_version" unless manifest["schema_version"] == 1
        state = manifest["expected_ui_state"].to_s
        errors << "#{prefix}: unknown state #{state.inspect}" unless States::ALL.include?(state)
        states << state if States::ALL.include?(state)
        errors << "#{prefix}: capture lacks explicit user confirmation" unless manifest.dig("manual_confirmation", "confirmed") == true
        frames = manifest["frames"]
        unless frames.is_a?(Array) && frames.any?
          errors << "#{prefix}: frames must be a non-empty array"
          return
        end

        frames.each_with_index do |frame, index|
          validate_frame(manifest_path.dirname, frame, "#{prefix}: frame #{index + 1}", errors:, warnings:, hashes:)
        end
      end

      def validate_frame(directory, frame, prefix, errors:, warnings:, hashes:)
        relative = Pathname(frame.fetch("path", ""))
        if relative.absolute? || relative.each_filename.any? { |part| part == ".." }
          errors << "#{prefix}: path must stay inside the capture directory"
          return
        end
        path = directory.join(relative).cleanpath
        unless path.file?
          errors << "#{prefix}: missing image #{relative}"
          return
        end

        bytes = path.binread
        info = ImageInfo.read(bytes)
        errors << "#{prefix}: width mismatch" unless frame["width"] == info["width"]
        errors << "#{prefix}: height mismatch" unless frame["height"] == info["height"]
        errors << "#{prefix}: format mismatch" unless frame["format"] == info["format"]
        actual_hash = Digest::SHA256.hexdigest(bytes)
        errors << "#{prefix}: SHA-256 mismatch" unless frame["sha256"] == actual_hash
        if hashes.key?(actual_hash)
          warnings << "#{prefix}: duplicate of #{hashes.fetch(actual_hash)}"
        else
          hashes[actual_hash] = path.to_s
        end
      rescue ImageInfo::Invalid => e
        errors << "#{prefix}: unreadable image: #{e.message}"
      end

      def validate_pairs(states, errors:, warnings:, required:)
        States::PAIRS.each do |detector, (positive_states, negative_states)|
          missing = []
          missing << "positive" if (states & positive_states).empty?
          missing << "negative" if (states & negative_states).empty?
          next if missing.empty?

          message = "#{detector}: missing #{missing.join(' and ')} example"
          (required ? errors : warnings) << message
        end
      end
    end
  end
end
