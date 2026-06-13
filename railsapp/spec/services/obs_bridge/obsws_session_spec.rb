# frozen_string_literal: true

require "spec_helper"

RSpec.describe ObsBridge::ObswsSession do
  let(:req) { instance_double("obs request client") }
  let(:events) { instance_double("obs events client", close: nil) }

  subject(:session) do
    described_class.new(req: req, events: events)
  end

  it "closes the events client when the session closes" do
    session.close

    expect(events).to have_received(:close).once
  end
end
