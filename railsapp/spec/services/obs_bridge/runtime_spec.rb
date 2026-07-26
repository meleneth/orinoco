# frozen_string_literal: true

require "spec_helper"
require "obs_bridge/affordance_context"
require "obs_bridge/affordance_host"
require "obs_bridge/backoff"
require "obs_bridge/bridge_state"
require "obs_bridge/inventory_reader"
require "obs_bridge/inventory_store"
require "obs_bridge/runtime"
require "obs_bridge/obsws_session_runner"

RSpec.describe ObsBridge::Runtime do
  class FakeThread
    MAX_JOIN_STEPS = 100

    def initialize(&block)
      @fiber = Fiber.new do
        block.call
        :done
      end
    end

    def step
      return if done?

      @fiber.resume
    end

    def join
      MAX_JOIN_STEPS.times do
        return self if done?

        step
      end

      raise "fake thread did not finish after #{MAX_JOIN_STEPS} steps"
    end

    def done?
      !@fiber.alive?
    end
  end

  class FakeThreadFactory
    attr_reader :thread

    def call(&block)
      @thread = FakeThread.new(&block)
    end
  end

  let(:state) do
    instance_double(
      ObsBridge::BridgeState,
      connected!: nil,
      heartbeat!: nil,
      disconnected!: nil
    )
  end

  let(:inventory_store) do
    instance_double(
      ObsBridge::InventoryStore,
      write_snapshot!: nil
    )
  end

  let(:session_runner) do
    instance_double(ObsBridge::ObswsSessionRunner)
  end

  let(:backoff) do
    instance_double(
      ObsBridge::Backoff,
      reset!: nil,
      snooze!: nil
    )
  end

  let(:logger) { instance_double(Proc, call: nil) }

  let(:inventory) do
    {
      scenes: [ { "sceneName" => "Clips" } ],
      scene_items_by_scene: {
        "Clips" => [
          { "sceneItemId" => 1, "sourceName" => "fight", "sceneItemEnabled" => true }
        ]
      }
    }
  end

  let(:mono_state) { Struct.new(:value).new(0.0) }
  let(:monotonic_clock) { -> { mono_state.value } }

  let(:sleep_calls) { [] }

  let(:sleeper) do
    lambda do |seconds|
      sleep_calls << seconds
      mono_state.value += seconds
      Fiber.yield
      nil
    end
  end

  let(:session) do
    instance_double(
      "obs session",
      fetch_inventory: inventory,
      poll_events: [],
      apply_request: nil,
      pump_once: nil
    ).tap do |sess|
      allow(sess).to receive(:pump_once) do |timeout:|
        mono_state.value += timeout
        Fiber.yield
        nil
      end
    end
  end

  let(:heartbeat_interval) { 0.1 }
  let(:idle_sleep) { 0.05 }

  let(:affordance_host) do
    instance_double(
      ObsBridge::AffordanceHost,
      event_types: [ "MediaInputPlaybackEnded" ],
      dispatch: nil
    )
  end

  let(:inventory_reader) { instance_double(ObsBridge::InventoryReader) }
  let(:affordance_config) { double("AffordanceConfig") }
  let(:obs_request_emitter) { instance_double(Proc) }

  let(:affordance_context) do
    instance_double(
      ObsBridge::AffordanceContext,
      inventory: inventory_reader,
      config: affordance_config,
      emit_request: obs_request_emitter
    )
  end

  let(:thread_factory) { FakeThreadFactory.new }

  subject(:runtime) do
    described_class.new(
      state: state,
      inventory_store: inventory_store,
      session_runner: session_runner,
      affordance_host: affordance_host,
      affordance_context: affordance_context,
      logger: logger,
      backoff: backoff,
      heartbeat_interval: heartbeat_interval,
      idle_sleep: idle_sleep,
      monotonic_clock: monotonic_clock,
      sleeper: sleeper,
      thread_factory: thread_factory
    )
  end

  def runtime_step
    thread_factory.thread.step
  end

  after do
    runtime.stop! if runtime.running?
  end

  it "connects, heartbeats, and hydrates inventory on start" do
    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    runtime.start!
    runtime_step

    expect(backoff).to have_received(:reset!)
    expect(state).to have_received(:connected!)
    expect(state).to have_received(:heartbeat!).once
    expect(inventory_store).to have_received(:write_snapshot!).with(
      scenes: inventory[:scenes],
      scene_items_by_scene: inventory[:scene_items_by_scene]
    )

    runtime_step
    runtime_step

    expect(state).to have_received(:heartbeat!).at_least(:twice)

    runtime.stop!

    expect(runtime.running?).to be(false)
    expect(state).to have_received(:disconnected!).at_least(:once)
  end

  it "refreshes inventory on demand while running" do
    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    runtime.start!
    runtime_step

    expect(session).to have_received(:fetch_inventory).once

    expect(runtime.refresh_inventory!).to be(true)

    runtime_step

    expect(session).to have_received(:fetch_inventory).twice
    expect(inventory_store).to have_received(:write_snapshot!).twice
  end

  it "does nothing when refresh_inventory! is called while stopped" do
    expect(runtime.refresh_inventory!).to be(false)
    expect(inventory_store).not_to have_received(:write_snapshot!)
  end

  it "queues obs requests while running" do
    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    request = {
      "requestType" => "SetSceneItemEnabled",
      "requestData" => {
        "sceneName" => "Clips",
        "sceneItemId" => 1,
        "sceneItemEnabled" => false
      }
    }

    runtime.start!
    runtime_step

    expect(state).to have_received(:connected!)

    expect(runtime.enqueue_obs_request!(request)).to be(true)

    runtime_step

    expect(session).to have_received(:apply_request).with(request)
  end

  it "does not queue obs requests while stopped" do
    request = { "requestType" => "RefreshSceneList" }

    expect(runtime.enqueue_obs_request!(request)).to be(false)
  end
  it "publishes screenshot results with reply topic and correlation" do
    result_calls = []
    result_publisher = lambda do |type, payload, topic:, correlation:|
      result_calls << {
        type: type,
        payload: payload,
        topic: topic,
        correlation: correlation
      }
    end
    screenshot_runtime = described_class.new(
      state: state,
      inventory_store: inventory_store,
      session_runner: session_runner,
      affordance_host: affordance_host,
      affordance_context: affordance_context,
      result_publisher: result_publisher,
      logger: logger,
      backoff: backoff,
      heartbeat_interval: heartbeat_interval,
      idle_sleep: idle_sleep,
      monotonic_clock: monotonic_clock,
      sleeper: sleeper,
      thread_factory: thread_factory
    )
    request = {
      "requestType" => "GetSourceScreenshot",
      "requestData" => { "imageFormat" => "png" }
    }
    command = {
      "request" => request,
      "reply_topic" => "orinoco.obs.screenshot.custom",
      "correlation" => { "request_id" => "req-1" }
    }

    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)
    allow(session).to receive(:apply_request).with(request).and_return(
      "imageData" => "data:image/png;base64,abc",
      "imageFormat" => "png",
      "sourceName" => "Gameplay",
      "activeSceneName" => "Gameplay"
    )

    screenshot_runtime.start!
    runtime_step

    expect(screenshot_runtime.enqueue_obs_request!(command)).to be(true)

    runtime_step

    expect(result_calls.length).to eq(1)
    expect(result_calls.first).to include(
      type: "obs.screenshot.captured",
      topic: "orinoco.obs.screenshot.custom",
      correlation: { "request_id" => "req-1" }
    )
    expect(result_calls.first.fetch(:payload)).to include(
      "imageData" => "data:image/png;base64,abc",
      "imageFormat" => "png",
      "sourceName" => "Gameplay",
      "activeSceneName" => "Gameplay"
    )
    expect(result_calls.first.fetch(:payload)).to include(
      "captureStartedAt",
      "captureCompletedAt",
      "captureDurationMs"
    )
  ensure
    screenshot_runtime&.stop!
  end

  it "publishes generic command results when a reply topic is provided" do
    result_calls = []
    result_publisher = lambda do |type, payload, topic:, correlation:|
      result_calls << {
        type: type,
        payload: payload,
        topic: topic,
        correlation: correlation
      }
    end
    command_runtime = described_class.new(
      state: state,
      inventory_store: inventory_store,
      session_runner: session_runner,
      affordance_host: affordance_host,
      affordance_context: affordance_context,
      result_publisher: result_publisher,
      logger: logger,
      backoff: backoff,
      heartbeat_interval: heartbeat_interval,
      idle_sleep: idle_sleep,
      monotonic_clock: monotonic_clock,
      sleeper: sleeper,
      thread_factory: thread_factory
    )
    request = {
      "requestType" => "GetCurrentProgramScene",
      "requestData" => {}
    }
    command = {
      "request" => request,
      "reply_topic" => "orinoco.obs.command.results",
      "correlation" => { "request_id" => "req-2" }
    }

    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)
    allow(session).to receive(:apply_request).with(request).and_return(
      "currentProgramSceneName" => "Gameplay"
    )

    command_runtime.start!
    runtime_step

    expect(command_runtime.enqueue_obs_request!(command)).to be(true)

    runtime_step

    expect(result_calls.length).to eq(1)
    expect(result_calls.first).to include(
      type: "obs.command.completed",
      topic: "orinoco.obs.command.results",
      correlation: { "request_id" => "req-2" }
    )
    expect(result_calls.first.fetch(:payload)).to include(
      "request" => request,
      "response" => { "currentProgramSceneName" => "Gameplay" }
    )
    expect(result_calls.first.fetch(:payload)).to include(
      "completedAt",
      "durationMs"
    )
  ensure
    command_runtime&.stop!
  end
  it "dispatches polled events to the affordance host" do
    event = {
      "eventType" => "MediaInputPlaybackEnded",
      "eventData" => { "inputUuid" => "abc-123" }
    }

    allow(session).to receive(:poll_events).and_return([ event ], [])
    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    runtime.start!
    runtime_step

    expect(affordance_host).to have_received(:dispatch).with(
      "MediaInputPlaybackEnded",
      event: { "inputUuid" => "abc-123" },
      context: affordance_context
    )
  end

  it "heartbeats while connected" do
    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    runtime.start!
    runtime_step
    runtime_step
    runtime_step

    expect(state).to have_received(:heartbeat!).at_least(:twice)
  end

  it "records runtime errors, disconnects with the error, and retries with backoff" do
    pump_calls = 0

    allow(session).to receive(:pump_once) do |timeout:|
      pump_calls += 1

      if pump_calls == 1
        raise StandardError, "socket went sideways"
      end

      mono_state.value += timeout
      Fiber.yield
      nil
    end

    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    runtime.start!
    runtime_step

    expect(state).to have_received(:disconnected!)
      .with(error: "runtime loop failed: StandardError: socket went sideways")
      .at_least(:once)
    expect(session_runner).to have_received(:run).at_least(:twice)
    expect(backoff).to have_received(:snooze!)
      .with(label: "obs-bridge/runtime")
      .at_least(:once)
  end

  it "marks disconnected on stop" do
    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    runtime.start!
    runtime_step

    expect(state).to have_received(:connected!)

    runtime.stop!

    expect(runtime.running?).to be(false)
    expect(state).to have_received(:disconnected!).at_least(:once)
  end

  it "raises if started twice" do
    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session)

    runtime.start!
    runtime_step

    expect { runtime.start! }.to raise_error("runtime already running")

    runtime.stop!
  end

  it "sleeps instead of pumping when the session does not support pump_once" do
    session_without_pump = Class.new do
      define_method(:initialize) do |inventory|
        @inventory = inventory
      end

      define_method(:fetch_inventory) do
        @inventory
      end

      define_method(:poll_events) do |timeout:|
        []
      end

      define_method(:apply_request) do |_request|
        nil
      end
    end.new(inventory)

    allow(session_without_pump).to receive(:respond_to?).and_call_original
    allow(session_without_pump).to receive(:respond_to?)
      .with(:poll_events)
      .and_return(true)
    allow(session_without_pump).to receive(:respond_to?)
      .with(:pump_once)
      .and_return(false)

    allow(session_runner).to receive(:run)
      .with(event_types: [ "MediaInputPlaybackEnded" ])
      .and_yield(session_without_pump)

    runtime.start!
    runtime_step

    expect(inventory_store).to have_received(:write_snapshot!).with(
      scenes: inventory[:scenes],
      scene_items_by_scene: inventory[:scene_items_by_scene]
    )
    expect(sleep_calls).to include(idle_sleep)

    runtime.stop!
  end
end
