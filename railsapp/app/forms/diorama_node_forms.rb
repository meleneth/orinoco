require "json"

module DioramaNodeForms
  def self.build(node)
    case node.kind
    when "trigger"
      Trigger.new(node)
    when "selector"
      Selector.new(node)
    when "condition"
      Condition.new(node)
    when "effect"
      Effect.new(node)
    when "asset"
      Asset.new(node)
    when "placement"
      Placement.new(node)
    when "binding"
      Binding.new(node)
    else
      Fallback.new(node)
    end
  end

  class Base
    include ActiveModel::Model
    include ActiveModel::Attributes

    attr_reader :node
    attr_accessor :name, :description

    validates :name, presence: true

    def initialize(node)
      @node = node
      load_from_node
    end

    def partial_name
      "diorama_node_forms/#{form_key}"
    end

    def form_key
      self.class.name.demodulize.underscore
    end

    def raw_data_editable?
      false
    end

    def raw_data
      pretty_data
    end

    def save
      return false unless valid?

      node.assign_attributes(
        name: name,
        description: description,
        data: data_payload
      )

      return true if node.save

      merge_node_errors
      false
    end

    def pretty_data
      JSON.pretty_generate(node.data || {})
    rescue StandardError
      "{}"
    end

    def validation_state
      node.validation_state
    end

    protected

    def load_from_node
      self.name = node.name
      self.description = node.description
    end

    def data_payload
      node.data || {}
    end

    def merge_node_errors
      node.errors.each do |error|
        errors.add(error.attribute, error.message)
      end
    end
  end

  class Trigger < Base
    EVENT_OPTIONS = [
      "obs.media_input.playback_ended",
      "twitch.chat.message_received"
    ].freeze

    attr_accessor :event

    validates :event, presence: true
    validates :event, inclusion: { in: EVENT_OPTIONS }, allow_blank: true

    def event_options
      EVENT_OPTIONS
    end

    protected

    def load_from_node
      super
      self.event = node.data.fetch("event", nil)
    end

    def data_payload
      { "event" => event }
    end
  end

  class Selector < Base
    SELECTOR_OPTIONS = [
      "obs.placements_for_input_uuid"
    ].freeze

    attr_accessor :selector, :args_input_uuid

    validates :selector, presence: true
    validates :selector, inclusion: { in: SELECTOR_OPTIONS }, allow_blank: true
    validates :args_input_uuid, presence: true

    def selector_options
      SELECTOR_OPTIONS
    end

    protected

    def load_from_node
      super
      self.selector = node.data.fetch("selector", nil)
      self.args_input_uuid = node.data.dig("args", "input_uuid")
    end

    def data_payload
      {
        "selector" => selector,
        "args" => {
          "input_uuid" => args_input_uuid
        }
      }
    end
  end

  class Condition < Base
    CONDITION_OPTIONS = [
      "scene_enabled_for_affordance"
    ].freeze

    attr_accessor :condition, :args_affordance, :args_scene_name

    validates :condition, presence: true
    validates :condition, inclusion: { in: CONDITION_OPTIONS }, allow_blank: true
    validates :args_affordance, presence: true
    validates :args_scene_name, presence: true

    def condition_options
      CONDITION_OPTIONS
    end

    protected

    def load_from_node
      super
      self.condition = node.data.fetch("condition", nil)
      self.args_affordance = node.data.dig("args", "affordance")
      self.args_scene_name = node.data.dig("args", "scene_name")
    end

    def data_payload
      {
        "condition" => condition,
        "args" => {
          "affordance" => args_affordance,
          "scene_name" => args_scene_name
        }
      }
    end
  end

  class Effect < Base
    EFFECT_OPTIONS = [
      "obs.scene_item.set_enabled"
    ].freeze

    attr_accessor :effect, :args_scene_name, :args_scene_item_id, :enabled

    validates :effect, presence: true
    validates :effect, inclusion: { in: EFFECT_OPTIONS }, allow_blank: true
    validates :args_scene_name, presence: true
    validates :args_scene_item_id, presence: true

    def effect_options
      EFFECT_OPTIONS
    end

    def enabled?
      ActiveModel::Type::Boolean.new.cast(enabled)
    end

    protected

    def load_from_node
      super
      self.effect = node.data.fetch("effect", nil)
      self.args_scene_name = node.data.dig("args", "scene_name")
      self.args_scene_item_id = node.data.dig("args", "scene_item_id")
      self.enabled = node.data.dig("args", "enabled")
    end

    def data_payload
      {
        "effect" => effect,
        "args" => {
          "scene_name" => args_scene_name,
          "scene_item_id" => args_scene_item_id,
          "enabled" => enabled?
        }
      }
    end
  end

  class Asset < Base
    attr_accessor :asset_type, :image_storage, :image_media_type, :image_encoding,
                  :image_data, :image_asset_ref, :image_sha256, :image_byte_size,
                  :image_width, :image_height

    validates :asset_type, presence: true
    validate :image_value_is_valid

    def raw_data_editable?
      false
    end

    def image_value
      DioramaImageValue.new(image_hash)
    end

    def inline_svg_preview?
      image_value.valid? && image_value.inline? && image_value.svg?
    end

    protected

    def load_from_node
      super
      self.asset_type = node.data.fetch("asset_type", nil)

      image = node.data["image"] || node.data["image_value"] || {}
      self.image_storage = image["storage"]
      self.image_media_type = image["media_type"]
      self.image_encoding = image["encoding"]
      self.image_data = image["data"]
      self.image_asset_ref = image["asset_ref"]
      self.image_sha256 = image["sha256"]
      self.image_byte_size = image["byte_size"]
      self.image_width = image["width"]
      self.image_height = image["height"]
    end

    def data_payload
      payload = { "asset_type" => asset_type }

      if asset_type == "image"
        payload["image"] = image_hash
      end

      payload
    end

    def image_hash
      {
        "storage" => image_storage,
        "media_type" => image_media_type,
        "encoding" => image_encoding,
        "data" => image_data,
        "asset_ref" => image_asset_ref,
        "sha256" => image_sha256,
        "byte_size" => cast_integer(image_byte_size),
        "width" => cast_integer(image_width),
        "height" => cast_integer(image_height)
      }.compact
    end

    def image_value_is_valid
      return unless asset_type == "image"

      image_value.validation_errors.each do |message|
        errors.add(:base, "image #{message}")
      end
    end

    def cast_integer(value)
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      value
    end
  end

  class JsonDataForm < Base
    attr_accessor :raw_data

    validates :raw_data, presence: true
    validate :raw_data_is_valid_json

    def raw_data_editable?
      true
    end

    def partial_name
      "diorama_node_forms/json_data_form"
    end

    def save
      return false unless valid?

      node.assign_attributes(
        name: name,
        description: description,
        data: parsed_raw_data
      )

      return true if node.save

      merge_node_errors
      false
    end

    protected

    def load_from_node
      super
      self.raw_data = pretty_data
    end

    def data_payload
      parsed_raw_data
    end

    def parsed_raw_data
      @parsed_raw_data ||= JSON.parse(raw_data.presence || "{}")
    end

    def raw_data_is_valid_json
      JSON.parse(raw_data.presence || "{}")
    rescue JSON::ParserError
      errors.add(:raw_data, "must be valid JSON")
    end
  end

  class Placement < JsonDataForm
  end

  class Binding < JsonDataForm
  end

  class Fallback < JsonDataForm
  end
end
