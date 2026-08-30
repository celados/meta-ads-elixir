defmodule MetaAds.Client do
  @moduledoc """
  The execution interface for Graph API calls.

  Applications normally call generated model functions rather than this module.
  It is public because pagination and escape hatches need the same behavior as
  generated operations.
  """

  alias MetaAds.{Config, Error, Params, Response}

  defstruct [:config, :http_client]

  @type t :: %__MODULE__{config: Config.t(), http_client: module()}

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) do
    attrs = Map.new(attrs)

    with {:ok, config} <- Config.new(attrs) do
      {:ok, %__MODULE__{config: config, http_client: config.http_client}}
    end
  end

  @doc """
  Executes a Graph API request against a versioned path.

  `path` must start with `/`. Generated calls always derive it from the client's
  configured API version, so a model cannot silently target another version.
  """
  @spec request(t(), :get | :post | :put | :delete, String.t(), map() | keyword(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def request(%__MODULE__{} = client, method, path, params \\ %{}, options \\ [])
      when method in [:get, :post, :put, :delete] and is_binary(path) and
             binary_part(path, 0, 1) == "/" do
    params =
      params
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> put_appsecret_proof(client.config)
      |> Params.encode()

    url = client.config.endpoint <> path
    headers = request_headers(client.config)
    {request_url, body} = request_parts(method, url, params)

    options =
      options
      |> Keyword.put_new(:timeout, client.config.timeout)
      |> Keyword.put_new(:connect_timeout, client.config.timeout)

    case client.http_client.request(method, request_url, headers, body, options) do
      {:ok, %Response{status: status} = response} when status in 200..299 -> {:ok, response}
      {:ok, response} -> {:error, Error.from_response(response)}
      {:error, reason} -> {:error, Error.from_transport(reason)}
    end
  end

  @doc "Follows a Graph API cursor URL returned in a prior response."
  @spec follow(t(), Response.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def follow(%__MODULE__{} = client, %Response{} = response, options \\ []) do
    case Response.next_page_url(response) do
      nil ->
        {:error, Error.validation("paging.next", "response has no next page")}

      url when is_binary(url) ->
        if String.starts_with?(url, client.config.endpoint <> "/") do
          call_next(client, url, options)
        else
          {:error, Error.validation("paging.next", "must stay on the configured Graph endpoint")}
        end
    end
  end

  @doc "Builds a versioned Graph API object path."
  @spec path(t(), String.t(), String.t(), String.t() | nil) :: String.t()
  def path(%__MODULE__{} = client, object_id, edge \\ "", base_path \\ nil)
      when is_binary(object_id) and object_id != "" do
    segments =
      [client.config.api_version, URI.encode(object_id, &URI.char_unreserved?/1), base_path, edge]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map(&String.trim_trailing(&1, "/"))

    "/" <> Enum.join(segments, "/")
  end

  defp call_next(client, url, options) do
    case client.http_client.request(:get, url, request_headers(client.config), nil, options) do
      {:ok, %Response{status: status} = response} when status in 200..299 -> {:ok, response}
      {:ok, response} -> {:error, Error.from_response(response)}
      {:error, reason} -> {:error, Error.from_transport(reason)}
    end
  end

  defp request_parts(:get, url, params), do: with_query(url, params)
  defp request_parts(:delete, url, params), do: with_query(url, params)
  defp request_parts(_method, url, params), do: {url, URI.encode_query(params)}

  defp with_query(url, params) do
    uri = URI.parse(url)
    query = merge_query(uri.query, URI.encode_query(params))
    {URI.to_string(%{uri | query: query}), nil}
  end

  defp merge_query(nil, ""), do: nil
  defp merge_query(nil, query) when is_binary(query), do: query
  defp merge_query(query, ""), do: query
  defp merge_query(query, addition), do: query <> "&" <> addition

  defp request_headers(%Config{} = config) do
    [
      {"authorization", "Bearer " <> config.access_token},
      {"accept", "application/json"}
    ]
  end

  defp put_appsecret_proof(params, %Config{app_secret: nil}), do: params

  defp put_appsecret_proof(params, %Config{} = config) do
    # Meta defines the proof as HMAC-SHA256(access_token, app_secret), hex-encoded.
    proof =
      :crypto.mac(:hmac, :sha256, config.app_secret, config.access_token)
      |> Base.encode16(case: :lower)

    Map.put(params, "appsecret_proof", proof)
  end
end
