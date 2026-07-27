class BasicSetupController < ApplicationController
  skip_before_action :ensure_obs_config!

  def index
    load_configs
  end

  def save
    load_configs

    @obs_config.assign_attributes(obs_config_params)
    @twitch_config.assign_attributes(twitch_config_params)
    @wos_brain_config.assign_attributes(wos_brain_affordance_params)
    @tank_game_config.assign_attributes(tank_game_affordance_params)
    auto_select_wos_source if params[:auto_wos_source].present?

    if [ @obs_config, @twitch_config, @wos_brain_config, @tank_game_config ].map(&:save).all?
      redirect_to basic_setup_index_path, notice: "Basic setup saved."
    else
      render :index, status: :unprocessable_entity
    end
  end

  private

  def load_configs
    @obs_config = ObsConfig.first_or_initialize
    @twitch_config = TwitchConfig.first_or_initialize
    @wos_brain_config = AffordanceConfig.fetch!(:wos_brain)
    @tank_game_config = AffordanceConfig.fetch!(:tank_game)
    @wos_source_options = wos_source_options
  end

  def auto_select_wos_source
    source_name = Wos::ScreenshotSourceSelector.new(@wos_source_options).call
    @wos_brain_config.screenshot_source_name = source_name if source_name.present?
  end

  def wos_source_options
    redis_url = Rails.application.config.x.scoreboard.redis_url
    return [] if redis_url.blank?

    inventory = ObsBridge::InventoryReader.new(
      redis: Redis.new(url: redis_url),
      bridge_id: Rails.application.config.x.obs_bridge.bridge_id || "obs_bridge"
    )

    inventory.input_placements_by_uuid.values.flatten.filter_map do |placement|
      placement["sourceName"] if placement.is_a?(Hash)
    end.uniq.sort
  rescue StandardError
    []
  end

  def obs_config_params
    params.require(:obs_config).permit(:host, :port)
  end

  def twitch_config_params
    params.require(:twitch_config).permit(:channel_name)
  end

  def wos_brain_affordance_params
    params.fetch(:wos_brain_affordance, ActionController::Parameters.new).permit(:enabled, :screenshot_source_name)
  end

  def tank_game_affordance_params
    params.fetch(:tank_game_affordance, ActionController::Parameters.new).permit(:enabled)
  end
end
