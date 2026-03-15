class ClipShowController < ApplicationController
  def index
    @scenes=SceneIndex.new(scene:"Clips")
    OBSWS::Requests::Client.new(host: @host, port: @port).run do |req|
      @scenes.refresh!(req)
    end

    @some_value=@scenes.by_name.keys
  end

  def play
    index_to_play = params[:id]
    clip_name     = params[:clip_name]

    OBSWS::Requests::Client.new(host: @host, port: @port).run do |req|

      req.set_scene_item_enabled("Clips", index_to_play.to_i, true)
      req.set_input_audio_monitor_type(clip_name, 'OBS_MONITORING_TYPE_MONITOR_ONLY')

    end

  end
end