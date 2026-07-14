# frozen_string_literal: true

require "spec_helper"
require "obs_bridge/supervisor"
require "obs_bridge/cmd"
require_relative "../../support/suppress_output"

RSpec.describe ObsBridge::Supervisor do
  let(:state) do
    instance_double(
      ObsBridge::BridgeState,
      desired_enabled?: false,
      set_last_error!: nil
    )
  end

  let(:runtime) do
    instance_double(
      ObsBridge::Runtime,
      running?: false,
      start!: nil,
      stop!: nil,
      refresh_inventory!: nil
    )
  end

  let(:control_consumer) do
    instance_double(ObsBridge::ControlConsumer)
  end

  let(:signal_queue) { Queue.new }

  let(:command_consumer) { instance_double(ObsBridge::CommandConsumer) }
  let(:runtime) { instance_double(ObsBridge::Runtime, refresh_inventory!: nil) }

  let(:runtime_factory) do
    -> { runtime }
  end

  subject(:supervisor) do
    described_class.new(
      state: state,
      control_consumer: control_consumer,
      command_consumer: command_consumer,
      runtime_factory: runtime_factory,
      signal_queue: signal_queue
    )
  end

  def run_in_thread(target = supervisor)
    Thread.new { target.run }
  end

  def wait_until(timeout: 1.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      return true if yield
      raise "timed out waiting for condition" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
  end

  def eventually(timeout: 1.0, &block)
    wait_until(timeout:) do
      block.call
      true
    rescue RSpec::Expectations::ExpectationNotMetError
      false
    end
  end

  before do
    allow(control_consumer).to receive(:run) do |stop:|
      sleep 0.01 until stop.call
    end

    allow(command_consumer).to receive(:run) do |stop:, dispatch:|
      sleep 0.01 until stop.call
    end

    allow(runtime).to receive(:running?).and_return(false)
    allow(runtime).to receive(:start!)
    allow(runtime).to receive(:stop!)
    allow(runtime).to receive(:refresh_inventory!)
    allow(state).to receive(:desired_enabled?).and_return(false)
    allow(state).to receive(:set_last_error!)
  end

  it "does not start the runtime when disabled" do
    thread = run_in_thread

    wait_until { supervisor.running? }

    expect(runtime).not_to have_received(:start!)

    supervisor.stop!
    thread.join
  end

  it "starts the runtime on boot when enabled" do
    allow(state).to receive(:desired_enabled?).and_return(true)

    suppress_output do
      thread = run_in_thread

      eventually { expect(runtime).to have_received(:start!).once }

      supervisor.stop!
      thread.join
    end
  end

  it "starts the runtime on reconcile after enable" do
    suppress_output do
      thread = run_in_thread
      wait_until { supervisor.running? }

      allow(state).to receive(:desired_enabled?).and_return(true)
      signal_queue << ObsBridge::Cmd.reconcile

      eventually { expect(runtime).to have_received(:start!).once }

      supervisor.stop!
      thread.join
    end
  end
end
