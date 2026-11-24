# frozen_string_literal: true

require "rails_helper"

RSpec.describe "D2R live projection", type: :request do
  let(:state) { { "level" => 42, "area" => "Black Marsh", "events" => [] } }

  before do
    allow(D2r::RunProjection).to receive(:new).and_return(instance_double(D2r::RunProjection, snapshot: state))
  end

  it "retains the JSON snapshot for external consumers" do
    get "/d2r/run", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(state)
  end

  it "returns a replaceable live fragment for stream reconnection" do
    get "/d2r/run", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.fragment(response.body)
    stream = document.at_css('turbo-stream[action="replace"][target="d2r_live_projection"]')
    expect(stream).to be_present
    expect(JSON.parse(stream.at_css('[data-d2r-run-target="state"]').text)).to eq(state)
  end
end
