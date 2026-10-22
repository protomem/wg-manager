defmodule WGM do
  @moduledoc """
  `WGM` — ядро системы управления WG/AWG-VPN на Elixir/OTP.

  Срез 1 (ядро) содержит:
  - доменную модель (`WGM.Node`, `WGM.Instance`, `WGM.Peer`, `WGM.Cascade`);
  - генерацию серверных и клиентских конфигов WG/AWG (`WGM.ConfigGenerator`);
  - валидацию параметров маскировки AWG (`WGM.AWGParamsValidator`);
  - обёртки для генерации ключей (`WGM.Keygen`, `WGM.CLI.Adapter`);
  - парсеры `wg show dump` / `awg show dump` (`WGM.Parser`).

  Срез 2 (агент) содержит read-only наблюдение за узлом (`WGM.Agent`).

  Срез 3 (контроллер) содержит:
  - хранилище желаемого состояния в exqlite (`WGM.Controller.Repo`);
  - команды CRUD узлов/инстансов/пиров с дедупликацией (`WGM.Controller`);
  - журнал команд и аудит без секретов;
  - адаптер подключения к агентам (`WGM.Controller.AgentAdapter`).

  Срез 4 (деплой) содержит OTP-приложение, релиз и systemd-юниты
  (`WGM.Application`, `rel/systemd`).

  Срез 6 (жизненный цикл инстансов) содержит:
  - converge-конвейер на агенте (`WGM.Agent.Converger`);
  - хранилище конфигов инстансов с бэкапами (`WGM.Agent.ConfigStore`);
  - расширение CLI-адаптера для `syncconf`/`up`/`down`;
  - команды запуска/остановки/перезапуска/удаления через контроллер.

  Срез 5 (клиент) содержит тонкую библиотеку для `iex` (`WGM.Client`):
  подключение к контроллеру, статус узлов/инстансов/пиров, справка.
  """
end
