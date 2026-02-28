#!/usr/bin/env ruby
# frozen_string_literal: true

# rubocop:disable Lint/MissingCopEnableDirective
# rubocop:disable Style/Documentation
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/ParameterLists
# rubocop:disable Lint/NonLocalExitFromIterator

require 'obsws'
require 'awesome_print'

HOST  = 'localhost'
PORT  = 4455
SCENE = 'Clips'

# ------------------ Utilities ------------------

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
    actual = [@min, base + (rand * 2 * j) - j].max
    warn "[#{label}] reconnecting in #{format('%.2f', actual)}s"
    sleep actual
  end
end

# ------------------ Command Types ------------------

module Cmd
  Stop    = Struct.new
  Refresh = Struct.new
  Play    = Struct.new(:name)
  Disable = Struct.new(:name)

  def self.stop = Stop.new
  def self.refresh = Refresh.new
  def self.play(name) = Play.new(name)
  def self.disable(name) = Disable.new(name)
end

# ------------------ Scene Index (cache) ------------------

class SceneIndex
  def initialize(scene:, logger: nil)
    @scene = scene
    @logger = logger || ->(msg) { warn msg }
    @mtx = Mutex.new
    @by_name = {}
  end

  attr_reader :scene

  def refresh!(req)
    fresh = {}
    req.get_scene_item_list(@scene).scene_items.each do |clip|
      fresh[clip[:sourceName]] = clip[:sceneItemId]
    end
    @mtx.synchronize { @by_name = fresh }
    @logger.call("[requests] refreshed scene index for #{@scene} (#{fresh.size})")
  end

  def id_for(name)
    @mtx.synchronize { @by_name[name] }
  end
end

# ------------------ Requests Pump ------------------

class RequestPump
  def initialize(host:, port:, index:, queue:, logger: nil, refresh_on_miss: true, stop_on_play_error: false)
    @host = host
    @port = port
    @index = index
    @q = queue
    @logger = logger || ->(msg) { warn msg }

    @refresh_on_miss = refresh_on_miss
    @stop_on_play_error = stop_on_play_error
  end

  def run
    backoff = Backoff.new

    loop do
      @logger.call('[requests] connecting...')
      OBSWS::Requests::Client.new(host: @host, port: @port).run do |req|
        backoff.reset!
        @index.refresh!(req)

        loop do
          cmd = @q.pop
          return if cmd.is_a?(Cmd::Stop)

          case cmd
          when Cmd::Refresh
            safe_request('refresh') { @index.refresh!(req) }

          when Cmd::Play
            play(req, cmd.name)

          when Cmd::Disable
            disable(req, cmd.name)

          else
            raise "Unknown command object: #{cmd.inspect}"
          end
        end
      end
    rescue OBSWS::OBSWSConnectionError, OBSWS::OBSWSError => e
      @logger.call("[requests] disconnected: #{e.class}: #{e.message}")
      backoff.snooze!('requests')
      next
    end
  end

  private

  def safe_request(label)
    yield
  rescue OBSWS::OBSWSRequestError => e
    @logger.call("[requests] #{label} failed req=#{e.req_name} code=#{e.code} msg=#{e.message}")
    raise if @stop_on_play_error && label == 'play'
  end

  def play(req, clip_name)
    safe_request('play') do
      id = @index.id_for(clip_name)

      if id.nil? && @refresh_on_miss
        @index.refresh!(req)
        id = @index.id_for(clip_name)
      end

      if id.nil?
        @logger.call("[requests] unknown clip #{clip_name.inspect} (not in #{@index.scene})")
        return
      end

      req.set_scene_item_enabled(@index.scene, id, true)
      req.set_input_audio_monitor_type(clip_name, 'OBS_MONITORING_TYPE_MONITOR_ONLY')
    end
  end

  def disable(req, clip_name)
    safe_request('disable') do
      id = @index.id_for(clip_name)
      if id.nil? && @refresh_on_miss
        @index.refresh!(req)
        id = @index.id_for(clip_name)
      end
      req.set_scene_item_enabled(@index.scene, id, false) if id
    end
  end
end

# ------------------ Events Loop ------------------

class EventLoop
  def initialize(host:, port:, logger: nil, &install_handlers)
    @host = host
    @port = port
    @logger = logger || ->(msg) { warn msg }
    @install_handlers = install_handlers
  end

  def run
    backoff = Backoff.new

    loop do
      @logger.call('[events] connecting...')
      events = OBSWS::Events::Client.new(host: @host, port: @port)

      @install_handlers&.call(events)

      backoff.reset!

      # obsws 0.6.2 often works without run (internal thread),
      # but if run exists and blocks, it's a clean "until disconnect" anchor.
      if events.respond_to?(:run)
        events.run
      else
        loop { sleep 1 }
      end
    rescue OBSWS::OBSWSConnectionError, OBSWS::OBSWSError => e
      @logger.call("[events] disconnected: #{e.class}: #{e.message}")
      backoff.snooze!('events')
      next
    end
  end
end

# ------------------ Public Facade ------------------

class ObsBridge
  def initialize(host:, port:, scene:, refresh_on_miss: true, stop_on_play_error: false, logger: nil)
    @logger = logger || ->(msg) { warn msg }

    @q = Queue.new
    @index = SceneIndex.new(scene: scene, logger: @logger)

    @pump = RequestPump.new(
      host: host,
      port: port,
      index: @index,
      queue: @q,
      logger: @logger,
      refresh_on_miss: refresh_on_miss,
      stop_on_play_error: stop_on_play_error
    )
  end

  def start!(&install_event_handlers)
    @requests_thread = Thread.new { @pump.run }
    @events_thread   = Thread.new do
      EventLoop.new(host: HOST, port: PORT, logger: @logger, &install_event_handlers).run
    end
  end

  def stop!
    @q << Cmd.stop
    @requests_thread&.join
    # events thread is intentionally “daemon style”; kill it on shutdown
    @events_thread&.kill
    @events_thread&.join
  end

  # intents
  def play(name)    = (@q << Cmd.play(name))
  def disable(name) = (@q << Cmd.disable(name))
  def refresh       = (@q << Cmd.refresh)
end

# ------------------ Clip sequencing ------------------

class ClipCycler
  def initialize(clips:, delay: 1.0)
    raise ArgumentError, 'clips must not be empty' if clips.empty?

    @clips = clips.freeze
    @delay = delay
    @index = 0
    @mtx = Mutex.new
  end

  def current
    @clips[@index]
  end

  def advance!
    @mtx.synchronize do
      @index = (@index + 1) % @clips.length
      @clips[@index]
    end
  end

  attr_reader :delay
end

# ------------------ App wiring ------------------

# clips = %w[wat mama why cowbell shaggy holycow familystyle]
clips = %w[fight]
cycler = ClipCycler.new(clips: clips, delay: 1.0)

bridge = ObsBridge.new(
  host: HOST,
  port: PORT,
  scene: SCENE,
  refresh_on_miss: true,
  stop_on_play_error: false
)

bridge.start! do |events|
  events.on :media_input_playback_ended do |evt|
    finished = evt.input_name
    next unless clips.include?(finished)

    ap "Finished playing: #{finished}"
    bridge.disable(finished)

    # keep callback short; schedule the next play outside it
    Thread.new do
      sleep cycler.delay
      bridge.play(cycler.advance!)
    end
  end
end

bridge.play(cycler.current)

trap('INT') do
  bridge.stop!
  exit
end
trap('TERM') do
  bridge.stop!
  exit
end

loop { sleep 1 }
