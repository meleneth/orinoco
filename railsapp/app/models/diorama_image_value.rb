require "base64"
require "cgi"

class DioramaImageValue
  SUPPORTED_STORAGE = %w[inline asset_ref].freeze
  SUPPORTED_MEDIA_TYPES = %w[
    image/svg+xml
    image/png
    image/jpeg
    image/webp
    image/gif
  ].freeze
  SUPPORTED_INLINE_ENCODINGS = %w[utf8 base64].freeze
  INLINE_MAX_BYTES = 256 * 1024

  attr_reader :value

  def initialize(value)
    @value = normalize_hash(value)
  end

  def storage
    value["storage"]
  end

  def media_type
    value["media_type"]
  end

  def encoding
    value["encoding"]
  end

  def data
    value["data"]
  end

  def asset_ref
    value["asset_ref"]
  end

  def sha256
    value["sha256"]
  end

  def byte_size
    value["byte_size"]
  end

  def width
    value["width"]
  end

  def height
    value["height"]
  end

  def inline?
    storage == "inline"
  end

  def asset_ref?
    storage == "asset_ref"
  end

  def svg?
    media_type == "image/svg+xml"
  end

  def raster?
    !svg?
  end

  def data_url
    return nil unless inline?

    if svg?
      "data:#{media_type};utf8,#{CGI.escape(data.to_s)}"
    else
      "data:#{media_type};base64,#{data}"
    end
  end

  def validation_errors
    errors = []

    errors.concat(required_field_errors)
    errors.concat(format_errors)
    errors.concat(storage_specific_errors)

    errors
  end

  def valid?
    validation_errors.empty?
  end

  private

  def normalize_hash(input)
    return {} unless input.is_a?(Hash)

    input.each_with_object({}) do |(key, val), output|
      output[key.to_s] = val
    end
  end

  def required_field_errors
    errors = []

    errors << "storage is required" if storage.blank?
    errors << "media_type is required" if media_type.blank?
    errors << "sha256 is required" if sha256.blank?

    if byte_size.nil?
      errors << "byte_size is required"
    elsif !byte_size.is_a?(Integer) || byte_size.negative?
      errors << "byte_size must be an integer greater than or equal to 0"
    end

    errors.concat(dimension_errors)
    errors
  end

  def format_errors
    errors = []

    if storage.present? && !SUPPORTED_STORAGE.include?(storage)
      errors << "storage must be one of: #{SUPPORTED_STORAGE.join(', ')}"
    end

    if media_type.present? && !SUPPORTED_MEDIA_TYPES.include?(media_type)
      errors << "media_type must be one of: #{SUPPORTED_MEDIA_TYPES.join(', ')}"
    end

    errors
  end

  def dimension_errors
    errors = []

    [ [ "width", width ], [ "height", height ] ].each do |field, raw_value|
      next if raw_value.nil?
      next if raw_value.is_a?(Integer) && raw_value.positive?

      errors << "#{field} must be a positive integer"
    end

    errors
  end

  def storage_specific_errors
    return [] unless SUPPORTED_STORAGE.include?(storage)

    errors = []

    if inline?
      errors << "data is required for inline storage" if data.blank?
      errors.concat(inline_encoding_errors)
      errors.concat(inline_size_errors)
      errors.concat(svg_safety_errors)
    end

    if asset_ref?
      errors << "asset_ref is required for asset_ref storage" if asset_ref.blank?
    end

    errors
  end

  def inline_encoding_errors
    errors = []

    if encoding.blank?
      errors << "encoding is required for inline storage"
      return errors
    end

    unless SUPPORTED_INLINE_ENCODINGS.include?(encoding)
      errors << "encoding must be one of: #{SUPPORTED_INLINE_ENCODINGS.join(', ')}"
      return errors
    end

    if svg? && encoding != "utf8"
      errors << "inline SVG must use utf8 encoding"
    end

    if raster? && encoding != "base64"
      errors << "inline raster images must use base64 encoding"
    end

    if raster? && encoding == "base64" && !valid_base64_data?
      errors << "inline raster images must use base64 encoding"
      errors << "inline raster images must contain valid base64 data"
    end

    errors
  end

  def inline_size_errors
    return [] unless byte_size.is_a?(Integer)
    return [] if byte_size <= INLINE_MAX_BYTES

    ["inline image exceeds maximum size of #{INLINE_MAX_BYTES} bytes"]
  end

  def svg_safety_errors
    return [] unless inline? && svg?

    # TODO: Run SVG sanitization and return security findings.
    []
  end

  def valid_base64_data?
    return false if data.blank?

    Base64.strict_decode64(data)
    true
  rescue ArgumentError
    false
  end
end
