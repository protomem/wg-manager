defmodule WGM do
  @moduledoc """
  `WGM` — ядро системы управления WG/AWG-VPN на Elixir/OTP.

  Срез 1 (ядро) содержит:
  - доменную модель (`WGM.Node`, `WGM.Instance`, `WGM.Peer`, `WGM.Cascade`);
  - генерацию серверных и клиентских конфигов WG/AWG (`WGM.ConfigGenerator`);
  - валидацию параметров маскировки AWG (`WGM.AWGParamsValidator`);
  - обёртки для генерации ключей (`WGM.Keygen`, `WGM.CLI.Adapter`);
  - парсеры `wg show dump` / `awg show dump` (`WGM.Parser`).
  """
end
