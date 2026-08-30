defmodule MetaAds.Response do
  @moduledoc """
  A decoded Graph API response.

  `:body` retains the canonical Graph envelope. Pagination is read through
  helper functions so callers do not need to know whether the result was a node
  or an edge.
  """

  defstruct [:status, :headers, :body]

  @type t :: %__MODULE__{status: pos_integer(), headers: keyword(), body: term()}

  @spec new(pos_integer(), list(), binary()) :: {:ok, t()} | {:error, term()}
  def new(status, headers, body) when is_integer(status) and status > 0 do
    with {:ok, decoded} <- decode(body) do
      {:ok, %__MODULE__{status: status, headers: normalize_headers(headers), body: decoded}}
    end
  end

  @doc "Returns a node body, or an edge's `data` array when present."
  @spec data(t()) :: term()
  def data(%__MODULE__{body: body}) when is_map(body) do
    case body do
      %{"data" => edge_data} -> edge_data
      _ -> body
    end
  end

  def data(%__MODULE__{body: body}), do: body

  @doc "Returns cursor metadata for an edge response."
  @spec paging(t()) :: map() | nil
  def paging(%__MODULE__{body: %{"paging" => paging}}) when is_map(paging), do: paging
  def paging(_response), do: nil

  @doc "Returns the absolute next-page URL, if Meta supplied one."
  @spec next_page_url(t()) :: String.t() | nil
  def next_page_url(%__MODULE__{body: %{"paging" => %{"next" => next}}}) when is_binary(next),
    do: next

  def next_page_url(_response), do: nil

  defp decode(body) when body in [nil, ""], do: {:ok, nil}

  defp decode(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:ok, body}
    end
  end

  defp decode(body), do: {:ok, body}

  defp normalize_headers(headers) do
    Enum.map(headers, fn {name, value} -> {normalize_name(name), normalize(value)} end)
  end

  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_list(name), do: List.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name

  defp normalize(value) when is_list(value), do: List.to_string(value)
  defp normalize(value), do: value
end
