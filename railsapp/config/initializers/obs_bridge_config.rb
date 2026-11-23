# config/initializers/obs_bridge_config.rb
return if ENV["SECRET_KEY_BASE_DUMMY"] == "1" || Rails.env.test?

Rails.application.config.x.scoreboard.redis_url =
  ENV.fetch("SCOREBOARD_REDIS_URL", "unset_scoreboard_redis_url")

Rails.application.config.x.obs_bridge.bridge_id =
  ENV.fetch("OBS_BRIDGE_ID", "obs_bridge")

Rails.application.config.x.obs_bridge.default_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV.fetch("OBS_BRIDGE_DEFAULT_ENABLED", "false"))

Rails.application.config.x.obs_bridge.obs_host =
  ENV.fetch("OBS_HOST", "unset_obs_host")

Rails.application.config.x.obs_bridge.obs_port =
  Integer(ENV.fetch("OBS_PORT", "4455"))
