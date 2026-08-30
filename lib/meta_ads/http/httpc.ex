defmodule MetaAds.HTTP.Httpc do
  @moduledoc false

  alias MetaAds.Response

  @behaviour MetaAds.HTTP

  @impl MetaAds.HTTP
  def request(method, url, headers, body, options) when is_binary(url) do
    {headers, content_type} = pop_content_type(headers)
    request = build_request(method, url, headers, content_type, body)

    http_options = [
      timeout: Keyword.get(options, :timeout, 15_000),
      connect_timeout: Keyword.get(options, :connect_timeout, 15_000),
      # Make the trust policy explicit so it cannot regress with an OTP default change.
      ssl: :httpc.ssl_verify_host_options(true),
      # Redirects are classified by Client so bearer credentials never cross origins.
      autoredirect: false
    ]

    case :httpc.request(method, request, http_options, body_format: :binary) do
      {:ok, {{_http_version, status, _phrase}, response_headers, response_body}} ->
        Response.new(status, response_headers, IO.iodata_to_binary(response_body))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request(method, url, headers, _content_type, _body)
       when method in [:get, :delete] do
    {String.to_charlist(url), encode_headers(headers)}
  end

  defp build_request(method, url, headers, content_type, body) when method in [:post, :put] do
    {
      String.to_charlist(url),
      encode_headers(headers),
      String.to_charlist(content_type || "application/x-www-form-urlencoded"),
      body(body)
    }
  end

  defp encode_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {String.to_charlist(name), String.to_charlist(value)}
    end)
  end

  defp pop_content_type(headers) do
    Enum.reduce(headers, {[], nil}, fn {name, value} = header, {headers, content_type} ->
      if String.downcase(name) == "content-type" do
        {headers, value}
      else
        {[header | headers], content_type}
      end
    end)
    |> then(fn {headers, content_type} -> {Enum.reverse(headers), content_type} end)
  end

  defp body(nil), do: []
  defp body(binary) when is_binary(binary), do: binary
end
