#!/usr/bin/env ruby
# frozen_string_literal: true

require "obsws"
require "awesome_print"

HOST  = "localhost"
PORT  = 4455
SCENE = "Clips"

# ------------------ Backoff ------------------

class Backoff
  def initialize(min: 0.25, max: 8.0, factor: 1.7, jitter: 0.25)
    @min = min
    @max = max
    @factor = factor
    @jitter = jitter
    @sleep = min
  end

  def reset! = (@sleep = @min)

  def snooze!(label)
    base = @sleep
    @sleep = [@sleep * @factor, @max].min

    j = base * @jitter
    actual = base + (rand * 2 * j) - j
    actual = @min if actual < @min

    warn "[#{label}] reconnecting in #{format('%.2f', actual)}s"
    sleep actual
  end
end

# ------------------ OBS Bridge ------------------

class ObsBridge
  def initialize(host:, port:, scene:)
    @host = host
    @port = port
    @scene = scene

    @q = Queue.new
    @stop = false

    @memes = {}
    @memes_mtx = Mutex.new

    # Discover obsws exception classes for 0.6.2 without guessing names wrong.
    @conn_error_classes = [
      "OBSWS::OBSWSConnectionError",
      "OBSWSConnectionError",
      "OBSWS::OBSWSError",
      "OBSWSError"
    ].filter_map { |name| constantize(name) }.uniq

    @request_error_class =
      constantize("OBSWS::OBSWSRequestError") ||
      constantize("OBSWSRequestError")

    if @conn_error_classes.empty?
      raise "Could not find obsws connection error classes. " \
            "Please check obsws gem exception names for your version."
    end

    unless @request_error_class
      raise "Could not find obsws request error class (OBSWSRequestError). " \
            "Please check obsws gem exception names for your version."
    end
  end

  def start!(&install_handlers)
    @install_handlers = install_handlers

    @requests_thread = Thread.new { requests_loop }
    @events_thread   = Thread.new { events_loop }
  end

  def stop!
    @stop = true
    @q << [:noop, nil]
    @requests_thread&.kill
    @events_thread&.kill
  end

  # public API (thread-safe)
  def play_clip(name) = (@q << [:play, name])
  def stop_clip(name) = (@q << [:stop, name])
  def refresh!         = (@q << [:refresh, nil])

  private

  def constantize(name)
    name.split("::").reduce(Object) do |ctx, const|
      return nil unless ctx.const_defined?(const, false) || ctx.const_defined?(const)
      ctx.const_get(const)
    end
  rescue NameError
    nil
  end

  def refresh_memes!(req)
    fresh = {}
    req.get_scene_item_list(@scene).scene_items.each do |clip|
      fresh[clip[:sourceName]] = clip[:sceneItemId]
    end
    @memes_mtx.synchronize { @memes = fresh }
    warn "[requests] refreshed memes (#{fresh.size})"
  end

  def scene_item_id(name)
    @memes_mtx.synchronize { @memes[name] }
  end

  def with_request_error_logging
    yield
  rescue @request_error_class => e
    # obsws 0.6.2: request errors include request name and a numeric code
    req_name = e.respond_to?(:req_name) ? e.req_name : "unknown_request"
    code     = e.respond_to?(:code) ? e.code : "unknown_code"
    warn "[requests] request failed #{req_name} code=#{code} msg=#{e.message}"
    # choose whether to swallow or re-raise per operation; default swallow here
  end

  # ---- Requests: one persistent connection + command queue ----
  def requests_loop
    backoff = Backoff.new

    until @stop
      begin
        warn "[requests] connecting..."
        OBSWS::Requests::Client.new(host: @host, port: @port).run do |req|
          backoff.reset!
          with_request_error_logging { refresh_memes!(req) }

          loop do
            break if @stop
            type, payload = @q.pop
            break if @stop

            case type
            when :noop
              next

            when :refresh
              with_request_error_logging { refresh_memes!(req) }

            when :play
              clip = payload
              with_request_error_logging do
                id = scene_item_id(clip)
                unless id
                  refresh_memes!(req)
                  id = scene_item_id(clip)
                end

                if id
                  req.set_scene_item_enabled(@scene, id, true)
                  req.set_input_audio_monitor_type(clip, "OBS_MONITORING_TYPE_MONITOR_ONLY")
                else
                  warn "[requests] unknown clip #{clip.inspect} (not in #{@scene} scene items)"
                end
              end

            when :stop
              clip = payload
              with_request_error_logging do
                id = scene_item_id(clip)
                unless id
                  refresh_memes!(req)
                  id = scene_item_id(clip)
                end
                req.set_scene_item_enabled(@scene, id, false) if id
              end

            else
              raise "Unknown command type: #{type.inspect}"
            end
          end
        end

      rescue *@conn_error_classes => e
        warn "[requests] disconnected: #{e.class}: #{e.message}"
        backoff.snooze!("requests")
        next
      end
    end
  end

  # ---- Events: one persistent connection, reconnect + reinstall handlers ----
  def events_loop
    backoff = Backoff.new

    until @stop
      begin
        warn "[events] connecting..."
        events = OBSWS::Events::Client.new(host: @host, port: @port)

        # reinstall handlers each reconnect (new client instance)
        if @install_handlers
          @install_handlers.call(events)
        else
          warn "[events] no handlers installed"
        end

        backoff.reset!

        # In 0.6.2 events often "just work" due to internal thread,
        # but if run exists and blocks, it's a good “stay here until disconnect” anchor.
        if events.respond_to?(:run)
          events.run
        else
          sleep 1 until @stop
        end

      rescue *@conn_error_classes => e
        warn "[events] disconnected: #{e.class}: #{e.message}"
        backoff.snooze!("events")
        next
      end
    end
  end
end

# ------------------ Your wiring ------------------

clips  = ["fight"]
#clips=['wat','mama','why','cowbell','shaggy','holycow','familystyle']

cycler = clips.cycle

bridge = ObsBridge.new(host: HOST, port: PORT, scene: SCENE)

bridge.start! do |events|
  events.on :media_input_playback_ended do |evt|
    clip = evt.input_name
    ap "Finished playing: #{clip}"

    bridge.stop_clip(clip)
    sleep 1
    bridge.play_clip(cycler.next)
  end
end

bridge.play_clip(clips.last)

trap("INT")  { bridge.stop!; exit }
trap("TERM") { bridge.stop!; exit }

sleep 1 while true
