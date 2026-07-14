# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Twitch chat", type: :request do
  before do
    redis = instance_double(Redis, lrange: [])
    allow(Redis).to receive(:new).and_return(redis)
  end

  it "renders the chat feed without channel setup controls" do
    get chat_index_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Twitch Chat")
    expect(response.body).to include("chat_feed")
    expect(response.body).not_to include("Channel name")
    expect(response.body).not_to include("Connect")
  end
end