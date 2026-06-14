module Overlay
  class StylePreset
    PRESETS = {
      "obs_panel" => "rounded-xl bg-black/70 p-4 text-white shadow-lg",
      "plain_text" => "text-white",
      "alert_box" => "rounded-xl bg-red-900/80 p-4 font-bold text-white"
    }.freeze

    def self.known?(key)
      PRESETS.key?(key.to_s)
    end

    def self.fetch!(key)
      PRESETS.fetch(key.to_s) do
        raise UnknownStylePresetError, "unknown style preset #{key.inspect}"
      end
    end

    def self.keys
      PRESETS.keys
    end
  end
end
