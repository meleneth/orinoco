# frozen_string_literal: true

module Orinoco
  module Messaging
    module Names
      BRIDGE_CONTROL_TOPIC = "orinoco.bridge.control"
      OBS_BRIDGE_CONTROL_QUEUE = "orinoco.obs.bridge.control"

      TWITCH_CHAT_MESSAGE_TOPIC = "orinoco.twitch.message.topic"
      TWITCH_CHAT_MESSAGE_QUEUE = "orinoco.twitch.message.queue"
      TWITCH_BRIDGE_CONTROL_QUEUE = "orinoco.twitch.bridge.control"
      SEVEN_TV_BRIDGE_CONTROL_QUEUE = "orinoco.7tv.bridge.control"

      OBS_COMMAND_TOPIC = "orinoco.obs.command"
      OBS_BRIDGE_COMMAND_QUEUE = "orinoco.obs.command.bridge"

      OBS_EVENTS_TOPIC = "orinoco.obs.events"
      OBS_EVENTS_QUEUE = "orinoco.obs.events.queue"

      OBS_SCREENSHOT_RESULT_TOPIC = "orinoco.obs.screenshot.results"
      OBS_SCREENSHOT_RESULT_QUEUE = "orinoco.obs.screenshot.results.queue"

      WOS_BOARD_RECOGNIZED_TOPIC = "orinoco.wos.board.recognized"
      WOS_BOARD_RECOGNIZED_QUEUE = "orinoco.wos.board.recognized.queue"
    end
  end
end
