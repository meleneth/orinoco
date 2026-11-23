# frozen_string_literal: true

require "zlib"

module VisualObserver
  module D2r
    class ImageInfo
      class Invalid < ArgumentError; end

      PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
      JPEG_SOF_MARKERS = ([ 0xC0, 0xC1, 0xC2, 0xC3 ] + [ 0xC5, 0xC6, 0xC7 ] + [ 0xC9, 0xCA, 0xCB ] + [ 0xCD, 0xCE, 0xCF ]).freeze

      def self.read(data)
        bytes = data.to_s.b
        return png(bytes) if bytes.start_with?(PNG_SIGNATURE)
        return jpeg(bytes) if bytes.start_with?("\xFF\xD8".b)

        raise Invalid, "frame is not a PNG or JPEG"
      end

      def self.png(bytes)
        raise Invalid, "truncated PNG" if bytes.bytesize < 24 || bytes.byteslice(12, 4) != "IHDR"

        width, height = bytes.byteslice(16, 8).unpack("N2")
        offset = PNG_SIGNATURE.bytesize
        chunks = []
        while offset + 12 <= bytes.bytesize
          length = bytes.byteslice(offset, 4).unpack1("N")
          type = bytes.byteslice(offset + 4, 4)
          chunk_end = offset + 12 + length
          raise Invalid, "truncated PNG chunk" if chunk_end > bytes.bytesize

          data = bytes.byteslice(offset + 8, length)
          expected_crc = bytes.byteslice(offset + 8 + length, 4).unpack1("N")
          raise Invalid, "PNG checksum mismatch" unless Zlib.crc32(type + data) == expected_crc

          chunks << type
          offset = chunk_end
          break if type == "IEND"
        end
        raise Invalid, "incomplete PNG" unless chunks.first == "IHDR" && chunks.include?("IDAT") && chunks.last == "IEND" && offset == bytes.bytesize

        validate_dimensions(width, height, "PNG")
      end
      private_class_method :png

      def self.jpeg(bytes)
        raise Invalid, "incomplete JPEG" unless bytes.end_with?("\xFF\xD9".b)

        offset = 2
        while offset + 3 < bytes.bytesize
          offset += 1 while offset < bytes.bytesize && bytes.getbyte(offset) != 0xFF
          offset += 1 while offset < bytes.bytesize && bytes.getbyte(offset) == 0xFF
          marker = bytes.getbyte(offset)
          offset += 1
          next if marker.nil? || marker == 0xD8 || marker == 0xD9

          length = bytes.byteslice(offset, 2)&.unpack1("n")
          raise Invalid, "truncated JPEG" unless length && length >= 2 && offset + length <= bytes.bytesize

          if JPEG_SOF_MARKERS.include?(marker)
            height, width = bytes.byteslice(offset + 3, 4).unpack("n2")
            return validate_dimensions(width, height, "JPEG")
          end
          offset += length
        end
        raise Invalid, "JPEG dimensions not found"
      end
      private_class_method :jpeg

      def self.validate_dimensions(width, height, format)
        raise Invalid, "invalid #{format} dimensions" unless width.to_i.positive? && height.to_i.positive?

        { "format" => format.downcase, "width" => width, "height" => height }
      end
      private_class_method :validate_dimensions
    end
  end
end
