# frozen_string_literal: true

class AffordanceConfig < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :config, presence: true

  before_validation :normalize_name
  before_validation :normalize_config

  scope :named, ->(name) { where(name: name.to_s) }

  def self.fetch!(name)
    find_or_create_by!(name: name.to_s) do |record|
      record.config = default_config_for(name)
    end
  end

  def self.for(name)
    find_by(name: name.to_s)
  end

  def self.default_config_for(name)
    case name.to_s
    when "clip_show"
      {
        "enabled" => false,
        "scenes" => []
      }
    when "wos_brain"
      {
        "enabled" => false,
        "scenes" => [],
        "ruleset_mode" => "auto",
        "manual_ruleset" => "base",
        "screenshot_source_name" => ""
      }
    when "d2r_observer"
      {
        "enabled" => false,
        "scenes" => [],
        "screenshot_source_name" => "",
        "interval_seconds" => 0.5,
        "idle_interval_seconds" => 60,
        "image_width" => 1920,
        "image_height" => 1200,
        "jpeg_quality" => 90
      }
    when "tank_game"
      {
        "enabled" => true,
        "trigger_command" => "!TankGame",
        "signup_command" => "!signup",
        "demo_command" => "!TankDemo",
        "aim_command" => "!aim",
        "weapon_command" => "!weapon",
        "signup_seconds" => 30,
        "fire_interval_seconds" => 5,
        "max_round_seconds" => 600,
        "scene_name" => "TankGame",
        "web_source_name" => "TankGameWebView",
        "width" => 1920,
        "height" => 1080
      }
    else
      {}
    end
  end

  def enabled
    enabled?
  end

  def enabled?
    ActiveModel::Type::Boolean.new.cast(config["enabled"])
  end

  def enabled=(value)
    self.config = config.merge("enabled" => ActiveModel::Type::Boolean.new.cast(value))
  end

  def scenes
    Array(config["scenes"]).map(&:to_s).uniq.sort
  end

  def scenes=(values)
    normalized =
      Array(values)
        .map(&:to_s)
        .map(&:strip)
        .reject(&:blank?)
        .uniq
        .sort

    self.config = config.merge("scenes" => normalized)
  end

  def enabled_for_scene?(scene_name)
    enabled? && scenes.include?(scene_name.to_s)
  end

  def ruleset_mode
    config["ruleset_mode"].to_s
  end

  def manual_ruleset
    config["manual_ruleset"].to_s
  end

  def screenshot_source_name
    config["screenshot_source_name"].to_s
  end

  def screenshot_source_name=(value)
    self.config = config.merge("screenshot_source_name" => value.to_s.strip)
  end

  private

  def normalize_name
    self.name = name.to_s.strip
  end

  def normalize_ruleset_mode(value)
    value.to_s == "manual" ? "manual" : "auto"
  end

  def normalize_manual_ruleset(value)
    allowed = %w[base hidden_letter fake_letter hidden_and_fake chat_correlation]
    normalized = value.to_s
    allowed.include?(normalized) ? normalized : "base"
  end

  def normalize_config
    self.config = (config || {}).deep_stringify_keys

    case name
    when "clip_show"
      self.enabled = false if config["enabled"].nil?
      self.scenes = config["scenes"]
    when "wos_brain", "d2r_observer"
      self.enabled = false if config["enabled"].nil?
      self.scenes = config["scenes"]
      normalized = { "screenshot_source_name" => config["screenshot_source_name"].to_s.strip }
      if name == "wos_brain"
        normalized.merge!(
          "ruleset_mode" => normalize_ruleset_mode(config["ruleset_mode"]),
          "manual_ruleset" => normalize_manual_ruleset(config["manual_ruleset"])
        )
      else
        defaults = self.class.default_config_for(:d2r_observer)
        normalized.merge!(
          "idle_interval_seconds" => bounded_integer(config["idle_interval_seconds"], default: defaults["idle_interval_seconds"], min: 60, max: 300),
          "interval_seconds" => bounded_float(config["interval_seconds"], default: defaults["interval_seconds"], min: 0.2, max: 10.0),
          "image_width" => bounded_integer(config["image_width"], default: defaults["image_width"], min: 160, max: 1920),
          "image_height" => bounded_integer(config["image_height"], default: defaults["image_height"], min: 100, max: 1200),
          "jpeg_quality" => bounded_integer(config["jpeg_quality"], default: defaults["jpeg_quality"], min: 1, max: 100)
        )
      end
      self.config = config.merge(normalized)
    when "tank_game"
      defaults = self.class.default_config_for(:tank_game)
      self.config = defaults.merge(config)
      self.enabled = defaults["enabled"] if config["enabled"].nil?
    end
  end

  def bounded_float(value, default:, min:, max:)
    Float(value || default).clamp(min, max)
  rescue ArgumentError, TypeError
    default
  end

  def bounded_integer(value, default:, min:, max:)
    Integer(value || default).clamp(min, max)
  rescue ArgumentError, TypeError
    default
  end
end
