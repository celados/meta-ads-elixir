defmodule MetaAds.Config do
  @moduledoc false

  defstruct [
    :access_token,
    :app_secret,
    :http_client,
    api_version: "v26.0",
    endpoint: "https://graph.facebook.com",
    timeout: 15_000
  ]

  @type t :: %__MODULE__{
          access_token: String.t(),
          app_secret: String.t() | nil,
          api_version: String.t(),
          endpoint: String.t(),
          http_client: module(),
          timeout: pos_integer()
        }

  @spec new(map()) :: {:ok, t()} | {:error, MetaAds.Error.t()}
  def new(attrs) when is_map(attrs) do
    access_token = string(attrs[:access_token])
    app_secret = optional_string(attrs[:app_secret])
    api_version = string(attrs[:api_version]) || "v26.0"
    endpoint = string(attrs[:endpoint]) || "https://graph.facebook.com"
    allow_insecure_localhost = attrs[:allow_insecure_localhost] == true
    http_client = attrs[:http_client] || MetaAds.HTTP.Httpc
    timeout = attrs[:timeout] || 15_000

    with :ok <- validate_presence("access_token", access_token),
         :ok <- validate_secret("app_secret", app_secret),
         :ok <- validate_api_version(api_version),
         {:ok, endpoint} <- validate_endpoint(endpoint, allow_insecure_localhost),
         :ok <- validate_http_client(http_client),
         :ok <- validate_timeout(timeout) do
      {:ok,
       %__MODULE__{
         access_token: access_token,
         app_secret: app_secret,
         api_version: api_version,
         endpoint: endpoint,
         http_client: http_client,
         timeout: timeout
       }}
    end
  end

  defp string(value) when is_binary(value), do: String.trim(value)
  defp string(_value), do: nil

  defp optional_string(nil), do: nil
  defp optional_string(value), do: string(value)

  defp validate_presence(_name, value) when is_binary(value) and value != "", do: :ok

  defp validate_presence(name, _value),
    do: {:error, MetaAds.Error.validation(name, "must be a non-empty string")}

  defp validate_secret(_name, nil), do: :ok

  defp validate_secret(name, value) do
    if is_binary(value) and value != "" do
      :ok
    else
      {:error, MetaAds.Error.validation(name, "must be nil or a non-empty string")}
    end
  end

  defp validate_api_version(value) do
    if Regex.match?(~r/^v\d+\.\d+$/, value),
      do: :ok,
      else: {:error, MetaAds.Error.validation("api_version", "must look like v26.0")}
  end

  defp validate_endpoint(value, allow_insecure_localhost) do
    with {:ok, uri} <- URI.new(value),
         :ok <- validate_origin(uri),
         :ok <- validate_endpoint_scheme(uri, allow_insecure_localhost) do
      normalized =
        uri
        |> Map.put(:scheme, String.downcase(uri.scheme))
        |> Map.put(:host, String.downcase(uri.host))
        |> Map.put(:path, nil)
        |> URI.to_string()

      {:ok, normalized}
    else
      _error ->
        {:error,
         MetaAds.Error.validation(
           "endpoint",
           "must be an origin-only HTTPS URL (loopback HTTP requires allow_insecure_localhost: true)"
         )}
    end
  end

  defp validate_origin(%URI{} = uri) do
    if is_binary(uri.scheme) and is_binary(uri.host) and uri.host != "" and
         uri.userinfo == nil and uri.query == nil and uri.fragment == nil and
         uri.path in [nil, "", "/"] do
      :ok
    else
      :error
    end
  end

  defp validate_endpoint_scheme(%URI{scheme: "https"}, _allow_insecure_localhost), do: :ok

  defp validate_endpoint_scheme(%URI{scheme: "http", host: host}, true)
       when host in ["localhost", "127.0.0.1", "::1"],
       do: :ok

  defp validate_endpoint_scheme(_uri, _allow_insecure_localhost), do: :error

  defp validate_http_client(module) when is_atom(module), do: :ok

  defp validate_http_client(_value),
    do: {:error, MetaAds.Error.validation("http_client", "must be a module")}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok

  defp validate_timeout(_value),
    do: {:error, MetaAds.Error.validation("timeout", "must be a positive integer")}
end
