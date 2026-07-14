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
    when "wos_brain"
      self.enabled = false if config["enabled"].nil?
      self.scenes = config["scenes"]
      self.config = config.merge(
        "ruleset_mode" => normalize_ruleset_mode(config["ruleset_mode"]),
        "manual_ruleset" => normalize_manual_ruleset(config["manual_ruleset"]),
        "screenshot_source_name" => config["screenshot_source_name"].to_s.strip
      )
    end
  end
end
