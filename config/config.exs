import Config

# По умолчанию приложение стартует без агента/контроллера.
# В релизе режим переопределяется в runtime.exs через WGM_MODE.
config :wgm, :mode, :none
