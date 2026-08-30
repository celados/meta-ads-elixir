defmodule MetaAds.HTTP.Httpc do
  @moduledoc false

  alias MetaAds.Response

  @behaviour MetaAds.HTTP

  @impl MetaAds.HTTP
  def request(method, url, headers, body, options) when is_binary(url) do
    request = {
      method,
      String.to_charlist(url),
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), String.to_charlist(value)}
      end),
      content_type(headers),
      body(body)
    }

    http_options = [
      timeout: Keyword.get(options, :timeout, 15_000),
      connect_timeout: Keyword.get(options, :timeout, 15_000),
      ssl: Keyword.get(options, :ssl, [])
    ]

    case :httpc.request(request, http_options) do
      {:ok, {{_http_version, status, _phrase}, response_headers, response_body}} ->
        Response.new(status, response_headers, IO.iodata_to_binary(response_body))

      error ->
        {:error, error}
    end
  end

  defp content_type(headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_name, value} -> String.to_charlist(value)
      nil -> String.to_charlist("application/x-www-form-urlencoded")
    end
  end

  defp body(nil), do: []
  defp body(binary) when is_binary(binary), do: binary
end
