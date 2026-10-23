defmodule WGM.HealthCheck.Adapter do
  @moduledoc """
  Behaviour-шов для активных проверок доступности.
  """

  @type target :: String.t()
  @type route ::
          [String.t()]
          | %{
              required(:interface) => String.t(),
              required(:source_ip) => String.t(),
              required(:target) => String.t()
            }

  @doc """
  Выполняет ICMP-ping до `target`.
  """
  @callback ping(target()) :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Выполняет сквозную проверку по маршруту `route`.

  Маршрут может быть списком идентификаторов инстансов или картой с полями
  `:interface`, `:source_ip` и `:target` для ping через туннель.
  """
  @callback end_to_end(route()) :: {:ok, String.t()} | {:error, String.t()}
end
