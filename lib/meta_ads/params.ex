defmodule MetaAds.Params do
  @moduledoc false

  alias MetaAds.Error

  @spec validate(keyword() | map(), list(map())) :: {:ok, map()} | {:error, Error.t()}
  def validate(params, spec_params) do
    params = normalize(params)
    spec_params = Enum.map(spec_params, &%{&1 | "name" => to_string(&1["name"])})

    with {:ok, params} <- validate_required(params, spec_params),
         {:ok, params} <- validate_enums(params, spec_params) do
      {:ok, params}
    end
  end

  @doc """
  Encodes Graph API complex parameters.

  Graph accepts JSON strings for object/list parameters, while field lists are
  conventionally comma-separated. Keeping this rule in one place prevents each
  generated operation from choosing its own encoding.
  """
  @spec encode(map()) :: %{optional(String.t()) => String.t()}
  def encode(params) do
    Map.new(params, fn
      {"fields", values} when is_list(values) ->
        {"fields", Enum.map_join(values, ",", &to_string/1)}

      {key, value} when is_list(value) or is_map(value) or is_tuple(value) ->
        {key, JSON.encode!(value)}

      {key, value} when is_boolean(value) ->
        {key, if(value, do: "true", else: "false")}

      {key, value} ->
        {key, to_string(value)}
    end)
  end

  defp normalize(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize(params) when is_list(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp validate_required(params, spec_params) do
    missing =
      spec_params
      |> Enum.filter(& &1["required"])
      |> Enum.map(& &1["name"])
      |> Enum.reject(&Map.has_key?(params, &1))

    if missing == [] do
      {:ok, params}
    else
      {:error,
       Error.validation("params", "missing required parameter(s): #{Enum.join(missing, ", ")}")}
    end
  end

  defp validate_enums(params, spec_params) do
    Enum.reduce_while(spec_params, {:ok, params}, fn param, {:ok, acc} ->
      name = param["name"]

      if Map.has_key?(acc, name) do
        validate_enum_value(param, Map.get(acc, name), acc)
      else
        {:cont, {:ok, acc}}
      end
    end)
  end

  defp validate_enum_value(%{"values" => values} = param, value, acc) do
    actual_values = enum_values(value, param)

    if Enum.all?(actual_values, &(&1 in values)) do
      {:cont, {:ok, acc}}
    else
      {:halt,
       {:error,
        Error.validation(
          "params.#{param["name"]}",
          "expected one of #{inspect(values)}, got: #{inspect(actual_values)}"
        )}}
    end
  end

  defp validate_enum_value(_param, _value, acc), do: {:cont, {:ok, acc}}

  defp enum_values(values, %{"type" => "list<" <> _}), do: List.wrap(values)
  defp enum_values(value, _param), do: [value]
end
