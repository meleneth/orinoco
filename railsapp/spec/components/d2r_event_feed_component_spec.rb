# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2rEventFeedComponent, type: :component do
  include ViewComponent::TestHelpers

  it "renders at most five escaped event messages" do
    events = 6.times.map do |index|
      {
        "type" => "d2r.area.changed",
        "at" => "2026-11-22T10:00:0#{index}Z",
        "message" => index.zero? ? "<script>alert(1)</script>" : "Area #{index}"
      }
    end

    html = render_inline(described_class.new(events: events)).to_html

    expect(html).to include('id="d2r_event_feed"')
    expect(html).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    expect(html).not_to include("Area 5")
    expect(html.scan("<li ").length).to eq(5)
  end
end
