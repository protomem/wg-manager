import Config

if config_env() == :prod do
  mode =
    case System.get_env("WGM_MODE") do
      "agent" -> :agent
      "controller" -> :controller
      _ -> :none
    end

  config :wgm, :mode, mode
end
