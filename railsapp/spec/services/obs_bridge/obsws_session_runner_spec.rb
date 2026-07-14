# frozen_string_literal: true

require "spec_helper"
require "obs_bridge/obsws_session"
require "obs_bridge/obsws_session_runner"

RSpec.describe ObsBridge::ObswsSessionRunner do
  class FakeRequestsClient
    class << self
      attr_reader :instances

      def reset!
        @instances = []
      end
    end

    attr_reader :closed

    def initialize(host:, port:)
      self.class.reset! unless self.class.instances
      self.class.instances << self
      @host = host
      @port = port
      @closed = false
    end

    def run
      yield :request_client
    ensure
      @closed = true
    end
  end

  class FailingRequestsClient
    def initialize(host:, port:)
      @host = host
      @port = port
    end

    def run
      raise SocketError, "getaddrinfo: name or service not known"
    end
  end
  class FakeEventsClient
    class << self
      attr_reader :instances

      def reset!
        @instances = []
      end
    end

    attr_reader :closed

    def initialize(host:, port:)
      self.class.reset! unless self.class.instances
      self.class.instances << self
      @host = host
      @port = port
      @closed = false
    end

    def on(_event_name)
      true
    end

    def close
      @closed = true
    end
  end

  before do
    FakeRequestsClient.reset!
    FakeEventsClient.reset!
  end

  subject(:runner) do
    described_class.new(
      host: "localhost",
      port: 4455,
      requests_client_class: FakeRequestsClient,
      events_client_class: FakeEventsClient
    )
  end

  it "closes the events client after the block finishes" do
    yielded_session = nil

    runner.run(event_types: [ "MediaInputPlaybackEnded" ]) do |session|
      yielded_session = session
    end

    expect(yielded_session).to be_a(ObsBridge::ObswsSession)
    expect(FakeRequestsClient.instances.size).to eq(1)
    expect(FakeRequestsClient.instances.first.closed).to be(true)
    expect(FakeEventsClient.instances.size).to eq(1)
    expect(FakeEventsClient.instances.first.closed).to be(true)
  end
  it "includes host and port in connection failures" do
    runner = described_class.new(
      host: "missing-obs-host",
      port: 4455,
      requests_client_class: FailingRequestsClient,
      events_client_class: FakeEventsClient
    )

    expect do
      runner.run(event_types: []) { |_session| }
    end.to raise_error(
      ObsBridge::ObswsSessionRunner::ConnectionError,
      /missing-obs-host:4455: SocketError: getaddrinfo/
    )
  end
end
