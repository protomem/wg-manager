import Config

if config_env() == :prod do
  config :wgm, :mode, WGM.Application.parse_mode(System.get_env("WGM_MODE"))
end
