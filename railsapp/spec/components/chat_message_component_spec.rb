# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatMessageComponent, type: :component do
  include ViewComponent::TestHelpers

  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(redis).to receive(:hgetall).with("twitch_emote_7tv").and_return({})
    allow(redis).to receive(:hgetall).with("global_emote_7tv").and_return({})
  end

  it "renders a parsed twitch chat message with emotes replaced" do
    message = TwitchChatBridge::Message.from_json(<<~JSON)
      {
        "tags": {
          "color": "#5F9EA0",
          "display_name": "QuantumApprentice",
          "twitch_emotes": {
            "emotesv2_7303302352f44b5cb112ba52f438c890": [
              {
                "startPosition": "42",
                "endPosition": "55"
              }
            ],
            "emotesv2_b8792b3f4be2493499640ce0d30350cb": [
              {
                "startPosition": "57",
                "endPosition": "74"
              }
            ],
            "emotesv2_35afd89499c240e7a57abcb30a7c0168": [
              {
                "startPosition": "0",
                "endPosition": "11"
              }
            ],
            "emotesv2_fe1ccb3a4e4b4b1c9851b30546490861": [
              {
                "startPosition": "13",
                "endPosition": "24"
              }
            ],
            "emotesv2_84b3b3e91a2d4395befc55a128463c36": [
              {
                "startPosition": "26",
                "endPosition": "40"
              }
            ]
          },
          "subscriber": true,
          "user_id": "176050880"
        },
        "emotes": [
          {
            "id": "emotesv2_7303302352f44b5cb112ba52f438c890",
            "url": "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_7303302352f44b5cb112ba52f438c890/default/dark/2.0",
            "start_idx": 42,
            "end_index": 55
          },
          {
            "id": "emotesv2_b8792b3f4be2493499640ce0d30350cb",
            "url": "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_b8792b3f4be2493499640ce0d30350cb/default/dark/2.0",
            "start_idx": 57,
            "end_index": 74
          },
          {
            "id": "emotesv2_35afd89499c240e7a57abcb30a7c0168",
            "url": "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_35afd89499c240e7a57abcb30a7c0168/default/dark/2.0",
            "start_idx": 0,
            "end_index": 11
          },
          {
            "id": "emotesv2_fe1ccb3a4e4b4b1c9851b30546490861",
            "url": "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_fe1ccb3a4e4b4b1c9851b30546490861/default/dark/2.0",
            "start_idx": 13,
            "end_index": 24
          },
          {
            "id": "emotesv2_84b3b3e91a2d4395befc55a128463c36",
            "url": "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_84b3b3e91a2d4395befc55a128463c36/default/dark/2.0",
            "start_idx": 26,
            "end_index": 40
          }
        ],
        "name": "quantumapprentice",
        "txt": "quantu22Burn quantu22Boom quantu22Dogmeat quantu22Vdeath quantu22Flamedance",
        "display_name": "QuantumApprentice"
      }
    JSON

    rendered = render_inline(described_class.new(message: message))
    html = rendered.to_html

    expect(html).to include('style="color: #5F9EA0"')
    expect(html).to include("QuantumApprentice:")
    expect(html.scan("<img ").length).to eq(5)
    expect(html).to include("https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_35afd89499c240e7a57abcb30a7c0168/default/dark/2.0")
    expect(html).to include("https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_84b3b3e91a2d4395befc55a128463c36/default/dark/2.0")
  end

  it "escapes arbitrary HTML and JavaScript in message text" do
    message = TwitchChatBridge::Message.new(
      tags: { color: "#123456", display_name: "safe_name" },
      emotes: [],
      name: "safe_name",
      txt: '<script>alert("xss")</script><img src=x onerror=alert(1)>'
    )

    html = render_inline(described_class.new(message: message)).to_html

    expect(html).not_to include("<script>")
    expect(html).not_to include("<img src=x")
    expect(html).to include('&lt;script&gt;alert("xss")&lt;/script&gt;')
    expect(html).to include("&lt;img src=x onerror=alert(1)&gt;")
  end

  it "escapes display names" do
    message = TwitchChatBridge::Message.new(
      tags: { color: "#123456", display_name: '<img src=x onerror=alert(1)>' },
      emotes: [],
      name: "fallback",
      txt: "hello"
    )

    html = render_inline(described_class.new(message: message)).to_html

    expect(html).not_to include('<img src=x onerror=alert(1)>')
    expect(html).to include("&lt;img src=x onerror=alert(1)&gt;:")
  end

  it "falls back when the chat color is unsafe" do
    message = TwitchChatBridge::Message.new(
      tags: { color: 'red; background-image: url(javascript:alert(1))', display_name: "melen" },
      emotes: [],
      name: "melen",
      txt: "hello"
    )

    html = render_inline(described_class.new(message: message)).to_html

    expect(html).to include('style="color: #ffffff"')
    expect(html).not_to include("javascript:alert")
  end

  it "renders 7TV emotes as images while escaping surrounding text" do
    allow(redis).to receive(:hgetall).with("twitch_emote_7tv").and_return({ "WidePeepo" => "01F6N8N3E8000" })

    message = TwitchChatBridge::Message.new(
      tags: { color: "#123456", display_name: "melen" },
      emotes: [],
      name: "melen",
      txt: "hello WidePeepo <script>alert(1)</script>"
    )

    html = render_inline(described_class.new(message: message)).to_html

    expect(html).to include('src="https://cdn.7tv.app/emote/01F6N8N3E8000/2x.webp"')
    expect(html).not_to include("<script>")
    expect(html).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
  end

  it "keeps twitch emote image markup rendered when replacing 7TV emotes" do
    allow(redis).to receive(:hgetall).with("twitch_emote_7tv").and_return({ "WidePeepo" => "01F6N8N3E8000" })

    message = TwitchChatBridge::Message.new(
      tags: { color: "#123456", display_name: "melen" },
      emotes: [
        {
          id: "emotesv2_35afd89499c240e7a57abcb30a7c0168",
          url: "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_35afd89499c240e7a57abcb30a7c0168/default/dark/2.0",
          start: 0,
          end: 10
        }
      ],
      name: "melen",
      txt: "TwitchWave WidePeepo"
    )

    html = render_inline(described_class.new(message: message)).to_html

    expect(html.scan("<img ").length).to eq(2)
    expect(html).to include('src="https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_35afd89499c240e7a57abcb30a7c0168/default/dark/2.0"')
    expect(html).to include('src="https://cdn.7tv.app/emote/01F6N8N3E8000/2x.webp"')
    expect(html).not_to include("&lt;img")
  end
end
