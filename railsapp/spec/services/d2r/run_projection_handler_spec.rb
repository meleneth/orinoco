# frozen_string_literal: true

require "rails_helper"

RSpec.describe D2r::RunProjectionHandler do
  let(:projection) { instance_double(D2r::RunProjection) }
  let(:broadcaster) { class_double(Turbo::StreamsChannel) }
  let(:logger) { instance_double(ActiveSupport::Logger, warn: nil) }
  let(:handler) { described_class.new(projection:, broadcaster:, logger:) }
  let(:events) do
    5.times.map do |index|
      { "type" => "d2r.area.changed", "at" => "2026-11-22T10:00:0#{index}Z", "message" => "Area #{index}" }
    end
  end

  it "projects and replaces the live feed with the latest five events" do
    event = instance_double(Orinoco::Pipeline::Event, type: "d2r.area.changed")
    allow(projection).to receive(:call).with(event).and_return("events" => events)
    allow(broadcaster).to receive(:broadcast_update_to)

    expect(handler.call(event)).to eq("events" => events)
    expect(broadcaster).to have_received(:broadcast_update_to).with(
      :d2r_events,
      target: "d2r_event_feed",
      layout: false,
      renderable: an_instance_of(D2rEventFeedComponent)
    )
  end

  it "does not rebroadcast hidden classifier chatter" do
    event = instance_double(Orinoco::Pipeline::Event, type: "d2r.state.changed")
    allow(projection).to receive(:call).with(event).and_return("events" => events)
    allow(broadcaster).to receive(:broadcast_update_to)

    handler.call(event)

    expect(broadcaster).not_to have_received(:broadcast_update_to)
  end
end
