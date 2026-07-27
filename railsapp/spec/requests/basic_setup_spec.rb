# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Basic setup", type: :request do
  before do
    allow_any_instance_of(BasicSetupController).to receive(:wos_source_options).and_return(
      ["Browser", "Display Capture"]
    )
  end

  describe "GET /basic_setup/index" do
    it "returns http success and renders Twitch config and affordance controls" do
      get "/basic_setup/index"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Twitch")
      expect(response.body).to include("Channel name")
      expect(response.body).to include("WOSBrain")
      expect(response.body).to include("Enable WOSBrain affordance")
      expect(response.body).to include("Screenshot source")
      expect(response.body).to include("Display Capture")
      expect(response.body).to include("Auto")
      expect(response.body).to include("TankGame")
      expect(response.body).to include("Enable TankGame affordance")
    end
  end

  describe "POST /basic_setup" do
    it "saves OBS, Twitch, WOSBrain, and TankGame config together" do
      post basic_setup_path, params: {
        obs_config: {
          host: "host.docker.internal",
          port: 4455
        },
        twitch_config: {
          channel_name: "orinoco_channel"
        },
        wos_brain_affordance: {
          enabled: "1",
          screenshot_source_name: "Browser"
        },
        tank_game_affordance: {
          enabled: "0"
        }
      }

      expect(response).to redirect_to(basic_setup_index_path)
      expect(ObsConfig.first.host).to eq("host.docker.internal")
      expect(ObsConfig.first.port).to eq(4455)
      expect(TwitchConfig.first.channel_name).to eq("orinoco_channel")
      expect(AffordanceConfig.fetch!(:wos_brain)).to be_enabled
      expect(AffordanceConfig.fetch!(:wos_brain).screenshot_source_name).to eq("Browser")
      expect(AffordanceConfig.fetch!(:tank_game)).not_to be_enabled
    end

    it "auto-selects a desktop-like WOSBrain screenshot source" do
      post basic_setup_path, params: {
        auto_wos_source: "1",
        obs_config: {
          host: "host.docker.internal",
          port: 4455
        },
        twitch_config: {
          channel_name: "orinoco_channel"
        },
        wos_brain_affordance: {
          enabled: "1",
          screenshot_source_name: "Browser"
        }
      }

      expect(response).to redirect_to(basic_setup_index_path)
      expect(AffordanceConfig.fetch!(:wos_brain).screenshot_source_name).to eq("Display Capture")
    end

    it "can disable the WOSBrain affordance" do
      AffordanceConfig.fetch!(:wos_brain).update!(enabled: true)

      post basic_setup_path, params: {
        obs_config: {
          host: "host.docker.internal",
          port: 4455
        },
        twitch_config: {
          channel_name: "orinoco_channel"
        },
        wos_brain_affordance: {
          enabled: "0"
        }
      }

      expect(response).to redirect_to(basic_setup_index_path)
      expect(AffordanceConfig.fetch!(:wos_brain)).not_to be_enabled
    end

    it "can enable and disable the TankGame affordance" do
      AffordanceConfig.fetch!(:tank_game).update!(enabled: true)

      post basic_setup_path, params: {
        obs_config: {
          host: "host.docker.internal",
          port: 4455
        },
        twitch_config: {
          channel_name: "orinoco_channel"
        },
        wos_brain_affordance: {
          enabled: "0"
        },
        tank_game_affordance: {
          enabled: "0"
        }
      }

      expect(response).to redirect_to(basic_setup_index_path)
      expect(AffordanceConfig.fetch!(:tank_game)).not_to be_enabled

      post basic_setup_path, params: {
        obs_config: {
          host: "host.docker.internal",
          port: 4455
        },
        twitch_config: {
          channel_name: "orinoco_channel"
        },
        wos_brain_affordance: {
          enabled: "0"
        },
        tank_game_affordance: {
          enabled: "1"
        }
      }

      expect(response).to redirect_to(basic_setup_index_path)
      expect(AffordanceConfig.fetch!(:tank_game)).to be_enabled
    end

    it "renders errors when Twitch channel is missing" do
      post basic_setup_path, params: {
        obs_config: {
          host: "host.docker.internal",
          port: 4455
        },
        twitch_config: {
          channel_name: ""
        },
        wos_brain_affordance: {
          enabled: "1"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Channel name")
    end
  end
end
