#!/usr/bin/env ruby
require "debug"
require "obsws"
require "awesome_print"

def play_clip(clipname)
    OBSWS::Requests::Client
    .new(host: "localhost", port:4455)
    .run do |client|

        memes = Hash.new;

        client.get_scene_item_list("Clips").scene_items.each{
            |clip|
            memes[clip[:sourceName]] = clip[:sceneItemId]

        }
        # ap memes
        client.set_scene_item_enabled("Clips",memes[clipname],true);
        client.set_input_audio_monitor_type(clipname,"OBS_MONITORING_TYPE_MONITOR_ONLY")

        # binding.break
    end
end

play_clip("why")

client = OBSWS::Events::Client
    .new(host:"localhost",port:4455)


clips=['wat','mama','why','cowbell','shaggy','holycow','familystyle']
index=0

client.on :media_input_playback_ended do
    |clip|
    ap "Finished playing: #{clip.input_name}"

    puts "before: #{index}"
    play_clip(clips[index])
    index += 1
    puts "after: #{index}"
    # play_clip(clips.sample)

end

# input = gets
# puts input

# client.run
loop do
    puts "sleeping"
    sleep 1
    puts "awaking"
end
