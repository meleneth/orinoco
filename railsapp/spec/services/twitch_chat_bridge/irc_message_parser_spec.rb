# spec/services/twitch_chat_bridge/irc_message_parser_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwitchChatBridge::IrcMessageParser do
  subject(:parser) do
    described_class.new(
      channel_name: "daresiel",
      bot_name: "justinfan493377"
    )
  end

  describe "#parse" do
    it "ignores Twitch welcome/server numeric messages" do
      raw_messages = [
        ":tmi.twitch.tv 001 justinfan493377 :Welcome, GLHF!",
        ":tmi.twitch.tv 002 justinfan493377 :Your host is tmi.twitch.tv",
        ":tmi.twitch.tv 003 justinfan493377 :This server is rather new",
        ":tmi.twitch.tv 004 justinfan493377 :-",
        ":tmi.twitch.tv 375 justinfan493377 :-",
        ":tmi.twitch.tv 372 justinfan493377 :You are in a maze of twisty passages, all alike.",
        ":tmi.twitch.tv 376 justinfan493377 :>"
      ]

      raw_messages.each do |raw_message|
        expect(parser.parse(raw_message)).to be_nil
      end
    end

    it "ignores join and names messages" do
      raw_messages = [
        ":justinfan493377!justinfan493377@justinfan493377.tmi.twitch.tv JOIN #daresiel",
        ":justinfan493377.tmi.twitch.tv 353 justinfan493377 = #daresiel :justinfan493377",
        ":justinfan493377.tmi.twitch.tv 366 justinfan493377 #daresiel :End of /NAMES list"
      ]

      raw_messages.each do |raw_message|
        expect(parser.parse(raw_message)).to be_nil
      end
    end

    it "ignores roomstate messages" do
      raw_message = "@emote-only=0;followers-only=-1;r9k=0;room-id=159825609;slow=0;subs-only=0 :tmi.twitch.tv ROOMSTATE #daresiel"

      expect(parser.parse(raw_message)).to be_nil
    end

    it "parses first-time chatter PRIVMSG tags" do
      raw_message = "@badge-info=;badges=;client-nonce=abc;color=;display-name=duchessDabbaDoo;emote-only=0;emotes=;first-msg=1;flags=;id=abc;mod=0;returning-chatter=0;room-id=159825609;subscriber=0;tmi-sent-ts=1776554770098;turbo=0;user-id=1516321509;user-type= :duchessdabbadoo!duchessdabbadoo@duchessdabbadoo.tmi.twitch.tv PRIVMSG #daresiel :hello"

      message = parser.parse(raw_message)

      expect(message).to have_attributes(
        name: "duchessdabbadoo",
        display_name: "duchessDabbaDoo",
        txt: "hello"
      )
      expect(message.tags).to include(
        color: "pink",
        display_name: "duchessDabbaDoo",
        subscriber: false,
        user_id: "1516321509"
      )
    end

    it "parses a twitch PRIVMSG into a Message" do
      raw_message = "@badge-info=;badges=;client-nonce=bf3bc37a26844f3daa9e2361372bf9a5;color=;display-name=Meleneth;emote-only=1;emotes=555555584:0-1/emotesv2_fb2fbc5b7bb6466c8eacabb477da92aa:3-12/emotesv2_0d8139b214a649c0b0405cc0134d2ddf:14-21;first-msg=0;flags=;id=cc57784b-fafe-45dc-93f6-795bbc46cfad;mod=0;returning-chatter=0;room-id=159825609;subscriber=0;tmi-sent-ts=1776554770098;turbo=0;user-id=39179420;user-type= :meleneth!meleneth@meleneth.tmi.twitch.tv PRIVMSG #daresiel :<3 daresiLove NeedHeal"

      message = parser.parse(raw_message)

      expect(message).to be_a(TwitchChatBridge::Message)
      expect(message.name).to eq("meleneth")
      expect(message.txt).to eq("<3 daresiLove NeedHeal")

      expect(message.tags).to include(
        color: "pink",
        display_name: "Meleneth",
        subscriber: false,
        user_id: "39179420"
      )

      expect(message.emotes).to eq([
        {
          id: "555555584",
          url: "https://static-cdn.jtvnw.net/emoticons/v2/555555584/default/dark/2.0",
          start: 0,
          end: 1
        },
        {
          id: "emotesv2_fb2fbc5b7bb6466c8eacabb477da92aa",
          url: "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_fb2fbc5b7bb6466c8eacabb477da92aa/default/dark/2.0",
          start: 3,
          end: 12
        },
        {
          id: "emotesv2_0d8139b214a649c0b0405cc0134d2ddf",
          url: "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_0d8139b214a649c0b0405cc0134d2ddf/default/dark/2.0",
          start: 14,
          end: 21
        }
      ])
    end
  end
end
