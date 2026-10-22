defmodule WGM.AWGParamsValidator do
  @moduledoc """
  Валидация параметров маскировки AmneziaWG.

  Лимиты:
  - Jc: 1–128 (или 0 для выключенной маскировки)
  - Jmin < Jmax < 1280
  - S1 ≤ 1132, S2 ≤ 1188, S1 + 56 ≠ S2
  - H1–H4: диапазоны без пересечений (или off/0-0 для выключенной маскировки)

  При выключенной маскировке (0/off/0-0 и H1=1..H4=4) конфиг совместим с WG.
  """

  alias WGM.Instance.AWGParams

  @type validation_result :: :ok | {:error, String.t()}

  @spec validate(AWGParams.t() | map()) :: validation_result()
  def validate(params) do
    with :ok <- validate_jc(params.jc),
         :ok <- validate_jmin_jmax(params.jmin, params.jmax),
         :ok <- validate_s_values(params.s1, params.s2),
         :ok <- validate_h_ranges(params),
         :ok <- validate_header_protection(params) do
      :ok
    end
  end

  @doc """
  Проверяет, выключена ли маскировка (WG-совместимый режим).

  WG-совместимый режим: Jc/Jmin/Jmax/S1/S2 равны нулю и H1–H4 содержат
  одно из значений «выключено»: `"0"`, `"off"`, `"0-0"` или стандартные
  WG-значения `"1".."4"`.
  """
  @spec masking_disabled?(AWGParams.t() | map()) :: boolean()
  def masking_disabled?(%AWGParams{} = params) do
    params.jc == 0 and
      params.jmin == 0 and
      params.jmax == 0 and
      params.s1 == 0 and
      params.s2 == 0 and
      h_disabled?(params.h1) and
      h_disabled?(params.h2) and
      h_disabled?(params.h3) and
      h_disabled?(params.h4)
  end

  def masking_disabled?(_), do: false

  defp h_disabled?(value) when value in ["0", "off", "0-0", "1", "2", "3", "4"], do: true
  defp h_disabled?(_), do: false

  defp validate_jc(0), do: :ok
  defp validate_jc(jc) when is_integer(jc) and jc >= 1 and jc <= 128, do: :ok
  defp validate_jc(_), do: {:error, "Jc must be between 1 and 128, or 0 for disabled masking"}

  defp validate_jmin_jmax(0, 0), do: :ok

  defp validate_jmin_jmax(jmin, jmax)
       when is_integer(jmin) and is_integer(jmax) and jmin < jmax and jmax < 1280,
       do: :ok

  defp validate_jmin_jmax(jmin, jmax) when jmin >= jmax,
    do: {:error, "Jmin must be less than Jmax"}

  defp validate_jmin_jmax(_, jmax) when jmax >= 1280,
    do: {:error, "Jmax must be less than 1280"}

  defp validate_jmin_jmax(_, _), do: {:error, "Jmin and Jmax must be valid integers"}

  defp validate_s_values(0, 0), do: :ok

  defp validate_s_values(s1, s2) when is_integer(s1) and is_integer(s2) do
    cond do
      s1 > 1132 -> {:error, "S1 must be at most 1132"}
      s2 > 1188 -> {:error, "S2 must be at most 1188"}
      s1 + 56 == s2 -> {:error, "S1 + 56 must not equal S2"}
      true -> :ok
    end
  end

  defp validate_s_values(_, _), do: {:error, "S1 and S2 must be valid integers"}

  defp validate_h_ranges(params) do
    ranges = [params.h1, params.h2, params.h3, params.h4]

    if Enum.all?(ranges, &h_disabled?/1) do
      :ok
    else
      parsed = Enum.map(ranges, &parse_range/1)

      case Enum.find(parsed, fn {status, _} -> status == :error end) do
        nil -> check_overlaps(Enum.map(parsed, fn {:ok, r} -> r end))
        {:error, raw} -> {:error, "Invalid H range format: #{raw}"}
      end
    end
  end

  defp validate_header_protection(params) do
    if header_protection_enabled?(params.header_protection_key) do
      with :ok <- validate_s_for_header_protection(params.s1, "S1"),
           :ok <- validate_s_for_header_protection(params.s2, "S2"),
           :ok <- validate_s_for_header_protection(params.s3, "S3"),
           :ok <- validate_s_for_header_protection(params.s4, "S4") do
        :ok
      end
    else
      :ok
    end
  end

  defp header_protection_enabled?(key) do
    is_binary(key) and String.trim(key) not in ["", "(none)"]
  end

  defp validate_s_for_header_protection(s, _name) when is_integer(s) and s >= 12, do: :ok

  defp validate_s_for_header_protection(s, name) when is_integer(s),
    do: {:error, "#{name} must be at least 12 when HeaderProtection is enabled"}

  defp validate_s_for_header_protection(_s, name),
    do: {:error, "#{name} must be a valid integer"}

  defp parse_range("off"), do: {:ok, nil}
  defp parse_range("0-0"), do: {:ok, nil}
  defp parse_range("0"), do: {:ok, nil}

  # Standard WG values for disabled masking: H1=1, H2=2, H3=3, H4=4.
  defp parse_range(raw) when raw in ["1", "2", "3", "4"], do: {:ok, nil}

  defp parse_range(raw) when is_binary(raw) do
    case String.split(raw, "-") do
      [start_str, end_str] ->
        with {start_val, ""} <- Integer.parse(start_str),
             {end_val, ""} <- Integer.parse(end_str),
             true <- start_val <= end_val do
          {:ok, {start_val, end_val}}
        else
          _ -> {:error, raw}
        end

      _ ->
        {:error, raw}
    end
  end

  defp parse_range(raw), do: {:error, raw}

  defp check_overlaps(ranges) do
    valid_ranges = Enum.reject(ranges, &is_nil/1)

    count = length(valid_ranges)

    overlaps? =
      for i <- 0..(count - 1)//1,
          j <- (i + 1)..(count - 1)//1,
          overlap?(Enum.at(valid_ranges, i), Enum.at(valid_ranges, j)),
          do: true

    if Enum.any?(overlaps?) do
      {:error, "H ranges must not overlap"}
    else
      :ok
    end
  end

  defp overlap?({a1, a2}, {b1, b2}), do: a1 <= b2 and b1 <= a2
end
