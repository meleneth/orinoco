# frozen_string_literal: true

require "rails_helper"

RSpec.describe "InteractionDemo", type: :request do
  let(:redis) { instance_double(Redis, get: nil) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
  end

  it "renders the manual toast form" do
    get interaction_demo_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Send Toast")
    expect(response.body).to include(interaction_demo_toast_path)
  end

  it "broadcasts a manual toast" do
    broadcaster = instance_double(Overlay::ToastBroadcaster, broadcast!: nil)
    allow(Overlay::ToastBroadcaster).to receive(:new).and_return(broadcaster)

    post interaction_demo_toast_path, params: {
      title: "Debug",
      message: "Shells should be visible",
      tone: "warning"
    }

    expect(broadcaster).to have_received(:broadcast!).with(
      title: "Debug",
      message: "Shells should be visible",
      tone: "warning"
    )
    expect(response).to redirect_to(interaction_demo_path)
  end
end
