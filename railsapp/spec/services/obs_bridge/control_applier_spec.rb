# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/suppress_output"

RSpec.describe ObsBridge::ControlApplier do
  let(:state) do
    instance_double(
      ObsBridge::BridgeState,
      enable!: nil,
      disable!: nil,
      capture_all_for: nil
    )
  end

  let(:signal_queue) { [] }

  subject(:applier) do
    described_class.new(
      state: state,
      signal_queue: signal_queue
    )
  end

  it "enables the bridge and signals reconcile" do
    result = applier.apply(
      ObsBridge::ControlMessage::Enable.new(bridge_id: "main", command_id: "abc")
    )

    expect(result).to eq(:enabled)
    expect(state).to have_received(:enable!).once
    expect(signal_queue).to eq([ ObsBridge::Cmd.reconcile ])
  end

  it "disables the bridge and signals reconcile" do
    result = applier.apply(
      ObsBridge::ControlMessage::Disable.new(bridge_id: "main", command_id: "abc")
    )

    expect(result).to eq(:disabled)
    expect(state).to have_received(:disable!).once
    expect(signal_queue).to eq([ ObsBridge::Cmd.reconcile ])
  end

  it "starts a capture-all window without queueing a signal" do
    result = applier.apply(
      ObsBridge::ControlMessage::CaptureAll.new(
        bridge_id: "main",
        duration_seconds: 900,
        command_id: "abc"
      )
    )

    expect(result).to eq(:capture_all)
    expect(state).to have_received(:capture_all_for).with(900)
    expect(signal_queue).to be_empty
  end

  it "signals refresh_inventory for refresh commands" do
    result = applier.apply(
      ObsBridge::ControlMessage::Refresh.new(bridge_id: "main", command_id: "abc")
    )

    expect(result).to eq(:refresh)
    expect(signal_queue).to eq([ ObsBridge::Cmd.refresh_inventory ])
  end

  it "ignores commands for other bridges" do
    suppress_output do
      result = applier.apply(
        ObsBridge::ControlMessage::Ignored.new(
          bridge_id: "main",
          actual_bridge_id: "other",
          command_id: "abc"
        )
      )

      expect(result).to eq(:ignored)
      expect(state).not_to have_received(:enable!)
      expect(state).not_to have_received(:disable!)
      expect(state).not_to have_received(:capture_all_for)
      expect(signal_queue).to be_empty
    end
  end
end
