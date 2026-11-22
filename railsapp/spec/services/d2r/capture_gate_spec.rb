# frozen_string_literal: true

require "spec_helper"
require "d2r/capture_gate"

RSpec.describe D2r::CaptureGate do
  class D2rGateRedis
    def get(key)
      @values ||= {}
      @values[key]
    end

    def set(key, value, **)
      @values ||= {}
      @values[key] = value
    end

    def del(key)
      @values ||= {}
      @values.delete(key)
    end
  end

  it "allows only one current request and ignores completion from another request" do
    now = Time.utc(2026, 11, 22, 1, 2, 3)
    gate = described_class.new(redis: D2rGateRedis.new, clock: -> { now })

    expect(gate).not_to be_pending
    gate.requested!("one")
    expect(gate).to be_pending
    gate.complete!("two")
    expect(gate).to be_pending
    gate.complete!("one")
    expect(gate).not_to be_pending
  end

  it "does not block on stale requests" do
    now = Time.utc(2026, 11, 22, 1, 2, 3)
    gate = described_class.new(redis: D2rGateRedis.new, stale_after: 1, clock: -> { now })
    gate.requested!("one")
    now += 2

    expect(gate).not_to be_pending
  end
end
