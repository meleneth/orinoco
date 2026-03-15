# orinoco
Streamer Tech


[twitch API](https://dev.twitch.tv/docs/api/)
[obsws ruby gem](https://rubygems.org/gems/obsws)


[ruby obs websocket library](https://github.com/hanazuki/ruby-obs-websocket)

Where we are: hacky scripts and direct-manipulating OBS in the web server

Where we're going:

a full Docker Compose setup with a ruby on rails frontend / backend, using postgres and goaws to build a dynamic stream manipulation platform.

Each integration bridge should have their own script running in the docker container, that subscribes to the service and the event queue and forwards events between them.

We should only subscribe to the events that correspond to features we are configured to use.

The plan is that the streamer installs this project via docker compose, then opens up a web page and configures it.  It should create the needed OBS scenes and setup dynamically as features are configured.

Wizards to build configuration, but being able to edit the pipelines after they've been configured is key, which means we're going to need some 'intent' metadata to make things make sense.

A Key Inspiration for this project, aside from needing it on Linux and Mac OS X in addition to windows, was that Hotwire allows db-backed data changes to push update a browser source.   This means we can have have one interface exposed to the streamer, and also have another interface that is rendered as an OBS browser source but pointed at our rails app to generate panels for scenes in OBS.

We should be able to make a 'chat event generifier' event pipeline such that we can define one set of triggers and it will work for discord and twitch, and provide responses to both as appropriate


Initial Target Functionalities:
Clip Triggers (enable a input source to 'play' it, with disable-on-finish event response)
metadata trackign of who triggered what how many times when
be able to setup chained plays - clip a, clip b, clip c
be able to random select a clip
be able to sequence the random clip select (i.e. always play these 2, then play 1 out of the 4 choices)
custom ruleset word games
