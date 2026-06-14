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
    when "fallback"
      Fallback.new(node)
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
    ASSET_TYPES = %w[image overlay_text_box].freeze
    TIMER_FIELD_NAMES = %i[timer_key duration_ms mode starts_on stops_on tick_rate_ms].freeze
    TIMER_FIELD_NAMES_TRIGGERING_VALIDATION = %i[timer_key duration_ms starts_on stops_on tick_rate_ms].freeze

    attr_accessor :asset_type, :image_storage, :image_media_type, :image_encoding,
                  :image_data, :image_asset_ref, :image_sha256, :image_byte_size,
                  :image_width, :image_height, :renderer_key, :element_key,
                  :style_preset, :content_template, :timer_key, :duration_ms,
                  :mode, :starts_on, :stops_on, :tick_rate_ms

    validates :asset_type, presence: true
    validates :asset_type, inclusion: { in: ASSET_TYPES }, allow_blank: true
    validate :image_value_is_valid
    validate :overlay_text_box_is_valid, if: :overlay_text_box?

    def raw_data_editable?
      false
    end

    def image_value
      DioramaImageValue.new(image_hash)
    end

    def inline_svg_preview?
      image_value.valid? && image_value.inline? && image_value.svg?
    end

    def overlay_text_box?
      asset_type == "overlay_text_box"
    end

    def overlay_timer_config
      return nil unless timer_fields_present?

      Overlay::TimerConfig.new(
        timer_key: timer_key,
        duration_ms: duration_ms,
        mode: mode,
        starts_on: starts_on,
        stops_on: stops_on,
        tick_rate_ms: tick_rate_ms
      )
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

      self.renderer_key = node.data.fetch("renderer_key", "text_box")
      self.element_key = node.data.fetch("element_key", node.slug.to_s.split(".").last)
      self.style_preset = node.data.fetch("style_preset", "obs_panel")
      self.content_template = node.data.fetch("content_template", "{{text}}")

      timer = node.data["timer"] || {}
      self.timer_key = timer["timer_key"]
      self.duration_ms = timer["duration_ms"]
      self.mode = timer["mode"]
      self.starts_on = timer["starts_on"]
      self.stops_on = timer["stops_on"]
      self.tick_rate_ms = timer["tick_rate_ms"]
    end

    def data_payload
      payload = { "asset_type" => asset_type }

      if asset_type == "image"
        payload["image"] = image_hash
      elsif overlay_text_box?
        payload["renderer_key"] = renderer_key
        payload["element_key"] = element_key
        payload["style_preset"] = style_preset
        payload["content_template"] = content_template

        timer = timer_payload
        payload["timer"] = timer if timer.present?
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

    def timer_payload
      return {} unless timer_fields_present?

      {
        "timer_key" => timer_key,
        "duration_ms" => cast_integer(duration_ms),
        "mode" => mode,
        "starts_on" => starts_on,
        "stops_on" => stops_on,
        "tick_rate_ms" => cast_integer(tick_rate_ms)
      }.compact
    end

    def timer_fields_present?
      TIMER_FIELD_NAMES_TRIGGERING_VALIDATION.any? { |field| send(field).present? }
    end

    def overlay_text_box_is_valid
      config = Overlay::ElementConfig.new(
        renderer_key: renderer_key,
        element_key: element_key,
        style_preset: style_preset,
        content_template: content_template,
        timer_config: overlay_timer_config
      )

      config.validation_errors.each do |message|
        errors.add(:base, message)
      end
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

  class Placement < Base
    PLACEMENT_TYPES = %w[fixed_overlay_position].freeze

    attr_accessor :placement_type, :anchor, :x, :y, :unit, :width, :height, :size_unit

    validates :placement_type, presence: true
    validates :placement_type, inclusion: { in: PLACEMENT_TYPES }, allow_blank: true
    validate :position_is_valid
    validate :size_is_valid

    def position_config
      Overlay::Position.new(anchor: anchor, x: x, y: y, unit: unit)
    end

    def size_config
      Overlay::Size.new(width: width, height: height, size_unit: size_unit)
    end

    protected

    def load_from_node
      super
      self.placement_type = node.data.fetch("placement_type", "fixed_overlay_position")

      position = node.data["position"] || {}
      self.anchor = node.data.fetch("anchor", position["anchor"])
      self.x = position["x"] || node.data["x"]
      self.y = position["y"] || node.data["y"]
      self.unit = position["unit"] || node.data["unit"] || "px"

      size = node.data["size"] || {}
      self.width = size["width"] || node.data["width"]
      self.height = size["height"] || node.data["height"]
      self.size_unit = size["size_unit"] || node.data["size_unit"] || "auto"
    end

    def data_payload
      {
        "placement_type" => placement_type,
        "anchor" => anchor,
        "position" => {
          "x" => cast_integer(x),
          "y" => cast_integer(y),
          "unit" => unit
        }.compact,
        "size" => {
          "width" => cast_integer(width),
          "height" => cast_integer(height),
          "size_unit" => size_unit
        }.compact
      }
    end

    def position_is_valid
      position_config.validation_errors.each do |message|
        errors.add(:base, message)
      end
    end

    def size_is_valid
      size_config.validation_errors.each do |message|
        errors.add(:base, message)
      end
    end

    def cast_integer(value)
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      value
    end
  end

  class Binding < Base
    BINDING_TYPES = %w[safe_text_template].freeze

    attr_accessor :binding_type, :template, :sample_context_json

    validates :binding_type, presence: true
    validates :binding_type, inclusion: { in: BINDING_TYPES }, allow_blank: true
    validates :template, presence: true
    validates :template, length: { maximum: 1_000 }
    validate :template_is_valid
    validate :sample_context_json_is_valid

    def preview_output
      return nil unless valid_template?

      Overlay::SafeTemplate.new(template).render(sample_context)
    rescue Overlay::InvalidTemplateError
      nil
    end

    def sample_context
      JSON.parse(sample_context_json.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    protected

    def load_from_node
      super
      self.binding_type = node.data.fetch("binding_type", "safe_text_template")
      self.template = node.data.fetch("template", "")

      sample_context = node.data["sample_context"] || node.data["sample_context_json"] || {}
      self.sample_context_json = sample_context.is_a?(String) ? sample_context : JSON.pretty_generate(sample_context)
    end

    def data_payload
      {
        "binding_type" => binding_type,
        "template" => template,
        "sample_context" => sample_context
      }
    end

    def template_is_valid
      return if template.blank?

      Overlay::SafeTemplate.new(template).validation_errors.each do |message|
        errors.add(:template, message)
      end
    end

    def sample_context_json_is_valid
      JSON.parse(sample_context_json.presence || "{}")
    rescue JSON::ParserError
      errors.add(:sample_context_json, "must be valid JSON")
    end

    def valid_template?
      Overlay::SafeTemplate.new(template).valid?
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

  class Fallback < JsonDataForm
  end
end
