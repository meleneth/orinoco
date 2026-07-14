# frozen_string_literal: true

module TwitchChatBridge
  class TwitchChatMessageProcessor
    def run
      TwitchChatProjectionWorker.new.run
    end

    def run_once
      TwitchChatProjectionWorker.new.run_once
    end
  end
end