# frozen_string_literal: true

require "obsws"

module ObsBridge
  class ObswsSessionRunner
    class ConnectionError < StandardError
      attr_reader :host, :port

      def initialize(host:, port:, cause:)
        @host = host
        @port = port
        super("failed to connect to OBS websocket at #{host}:#{port}: #{cause.class}: #{cause.message}")
      end
    end

    def initialize(
      host:,
      port:,
      requests_client_class: OBSWS::Requests::Client,
      events_client_class: OBSWS::Events::Client
    )
      @host = host
      @port = port
      @requests_client_class = requests_client_class
      @events_client_class = events_client_class
    end

    def run(event_types: [])
      yielded_from_client = false
      req = connected_requests_client

      req.run do |requests|
        yielded_from_client = true
        events = @events_client_class.new(host: @host, port: @port)
        session = ObswsSession.new(req: requests, events: events)

        session.subscribe!(event_types)
        yield session
      ensure
        session&.close
      end
    rescue StandardError => e
      raise if yielded_from_client || e.is_a?(ConnectionError)

      raise ConnectionError.new(host: @host, port: @port, cause: e)
    end

    private

    def connected_requests_client
      @requests_client_class.new(host: @host, port: @port)
    rescue StandardError => e
      raise ConnectionError.new(host: @host, port: @port, cause: e)
    end
  end
end