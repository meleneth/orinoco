obs websocket sends and receives events

twitch api sends and receives events

sns/sqs make event pipelines easy to reason about, and we can self-host via goaws

ruby on rails, particularly with Hotwire, makes for a nice database-backed web backend that can do synchable things via websockets (app-style, not page-style interactions)

So the goal is to throw these in a blender and hit 'puree'

The eventual goal is to present a local web UI that allows you to configure events, triggers, and transformations of your stream over time in an event driven fashion.

It would be nice to be able to interact with the OBS metadata and make sure needed scenes exist, create them if they don't, including plugin configuration.

Not all mods are currently configurable via API, so part of this might be contributing API configuration to various OBS plugins.

The local server should also be powering one or more obs browser sources.  


