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

    {request_url, body} = request_parts(method, client.config.endpoint <> path, params)
    headers = request_headers(client.config, body)

    execute(client, method, request_url, headers, body, options)
  end

  @doc "Follows a Graph API cursor URL returned in a prior response."
  @spec follow(t(), Response.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def follow(%__MODULE__{} = client, %Response{} = response, options \\ []) do
    case Response.next_page_url(response) do
      nil ->
        {:error, Error.validation("paging.next", "response has no next page")}

      url when is_binary(url) ->
        if same_origin?(url, client.config.endpoint) do
          execute(client, :get, url, request_headers(client.config, nil), nil, options)
        else
          {:error, Error.validation("paging.next", "must stay on the configured Graph endpoint")}
        end
    end
  end

  @doc "Builds a versioned Graph API object path."
  @spec path(t(), String.t(), String.t(), String.t() | nil) :: String.t()
  def path(%__MODULE__{} = client, object_id, edge \\ "", base_path \\ nil)
      when is_binary(object_id) and object_id != "" do
    encoded_object_id = URI.encode(object_id, &URI.char_unreserved?/1)

    segments =
      if base_path in [nil, ""] do
        [client.config.api_version, encoded_object_id, edge]
      else
        # Meta's basePath replaces the ordinary node/edge prefix order.
        [client.config.api_version, base_path, encoded_object_id]
      end
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map(&String.trim(&1, "/"))

    "/" <> Enum.join(segments, "/")
  end

  defp execute(client, method, url, headers, body, options) do
    options =
      options
      |> Keyword.put_new(:timeout, client.config.timeout)
      |> Keyword.put_new(:connect_timeout, client.config.timeout)

    client.http_client.request(method, url, headers, body, options)
    |> classify_response()
  end

  defp classify_response({:ok, %Response{} = response}) do
    if graph_error?(response) or response.status not in 200..299 do
      {:error, Error.from_response(response)}
    else
      {:ok, response}
    end
  end

  defp classify_response({:error, reason}), do: {:error, Error.from_transport(reason)}

  defp graph_error?(%Response{body: body}) when is_map(body), do: Map.has_key?(body, "error")
  defp graph_error?(_response), do: false

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

  defp request_headers(%Config{} = config, body) do
    headers = [
      {"authorization", "Bearer " <> config.access_token},
      {"accept", "application/json"}
    ]

    if is_binary(body) do
      [{"content-type", "application/x-www-form-urlencoded"} | headers]
    else
      headers
    end
  end

  defp same_origin?(url, endpoint) do
    with {:ok, page_uri} <- URI.new(url),
         {:ok, endpoint_uri} <- URI.new(endpoint) do
      page_uri.userinfo == nil and page_uri.fragment == nil and
        origin(page_uri) == origin(endpoint_uri)
    else
      _error -> false
    end
  end

  defp origin(%URI{} = uri), do: {uri.scheme, uri.host, uri.port || default_port(uri.scheme)}

  defp default_port("https"), do: 443
  defp default_port("http"), do: 80
  defp default_port(_scheme), do: nil

  defp put_appsecret_proof(params, %Config{app_secret: nil}), do: params

  defp put_appsecret_proof(params, %Config{} = config) do
    # Meta defines the proof as HMAC-SHA256(access_token, app_secret), hex-encoded.
    proof =
      :crypto.mac(:hmac, :sha256, config.app_secret, config.access_token)
      |> Base.encode16(case: :lower)

    Map.put(params, "appsecret_proof", proof)
  end
end
