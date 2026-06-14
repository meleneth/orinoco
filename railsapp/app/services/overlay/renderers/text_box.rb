module Overlay
  module Renderers
    class TextBox
      def initialize(element_config:, placement: nil, binding:, context:)
        @element_config = element_config
        @placement = placement
        @binding = binding
        @context = context || {}
      end

      def render
        element_config.validate!
        resolved_position.validate!

        content = safe_template.render(context)
        classes = Overlay::StylePreset.fetch!(element_config.style_preset)
        style = [ resolved_position.css_declarations, size_declarations ].join

        %(<div class="#{ERB::Util.html_escape(classes)}" style="#{ERB::Util.html_escape(style)}" data-element-key="#{ERB::Util.html_escape(element_config.element_key)}">#{content}</div>)
      end

      private

      attr_reader :element_config, :placement, :binding, :context

      def resolved_position
        placement || element_config.position || raise(Overlay::InvalidConfigError, "position is required")
      end

      def safe_template
        Overlay::SafeTemplate.new(template_source)
      end

      def template_source
        binding&.template.presence || element_config.content_template
      end

      def size_declarations
        return "" unless element_config.respond_to?(:size) && element_config.size

        element_config.size.css_declarations
      end
    end
  end
end
