# frozen_string_literal: true

require "vips"

module Wos
  class ImageLoader
    def self.load(path)
      Vips::Image.new_from_file(path.to_s, access: :random)
    end
  end
end
