defmodule WGM.Agent.Checker do
  @moduledoc """
  Запуск активных проверок на стороне агента.
  """

  alias WGM.Check

  @default_ping_target "1.1.1.1"

  @spec run_active(String.t(), atom(), String.t() | [String.t()] | nil, module()) ::
          Check.Result.t()
  def run_active(node_id, :ping, target, adapter) do
    target = target || @default_ping_target

    case adapter.ping(target) do
      {:ok, detail} ->
        ok_result(node_id, :ping, detail)

      {:error, detail} ->
        error_result(node_id, :ping, detail)
    end
  end

  def run_active(node_id, :end_to_end, route, adapter) when is_list(route) or is_map(route) do
    case adapter.end_to_end(route) do
      {:ok, detail} ->
        ok_result(node_id, :end_to_end, detail)

      {:error, detail} ->
        error_result(node_id, :end_to_end, detail)
    end
  end

  defp ok_result(node_id, kind, detail) do
    checked_at = DateTime.utc_now()

    %Check.Result{
      node_id: node_id,
      instance_id: nil,
      peer_id: nil,
      kind: kind,
      status: :ok,
      detail: detail,
      checked_at: checked_at,
      last_success_at: checked_at
    }
  end

  defp error_result(node_id, kind, detail) do
    %Check.Result{
      node_id: node_id,
      instance_id: nil,
      peer_id: nil,
      kind: kind,
      status: :error,
      detail: detail,
      checked_at: DateTime.utc_now(),
      last_success_at: nil
    }
  end
end
