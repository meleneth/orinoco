soon:
figure out which twitch integration library to use - [http://rubygems.org](http://rubygems.org), search for twitch

get rails site running via docker and foreman for all devs

integrate View Component for UI rendering w/tailwind classes

follow the Hotwire example to get an Overlay going

make a Clipshow affordance for doing QA style clip management

  be able to import clip names from an auto-discovered scene

  be able to trigger clips to be able to play

Let it be Known that the event pipeline is currently SNS/SQS, locally hosted via a goaws container

Integrate SNS / SQS via GoAWS - the server is running, but we don't have scripts setup to publish events and we don't have scripts setup to consume events

integrate obsws into the event pipeline

we will want to maintain a master list of events per-domain (i.e. obs, twitch, etc) so we can subscribe to them and also because we only want to let known event types pass

integrate the long-running processes that will be talking to obs 

integrate the long-running processes that will be talking to twitch


later:

come up with an event configuration UI.  what events in what domains we're subscribed to, and what events we want to send.

trigger configuration UI.  Streamer bot has it right that everything needs it's own configuration place, but lost the game in making the links be not-navigable

event pipeline config - from the web page we'll want to be able to maintain what the pipeline looks like - what SNS queues are listening for events, and which SQS queues they publish the events to.  A lot of this should 'just work' because we're making things that require specific wiring, but we should be able to view the setup as well

figure out if we care about multi user access.  password sniffing is bad and encryption is tricky, but profiles is still a thing? devise ruby gem



done:

compose.yml to configure docker compose to run rails, gowaws, opentelemetry, postgres (likely using mobilis to kickstart, it's a lot of wiring)

install rbenv and ruby - instructions in devsetup.md

get obsws to control obs via a script

