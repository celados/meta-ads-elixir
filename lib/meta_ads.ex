defmodule MetaAds do
  @moduledoc """
  Elixir SDK for the Meta Marketing API.

  The public interface is intentionally small: create a `MetaAds.Client`, then
  call operations on modules under `MetaAds.Models`. Generated modules contain
  operation metadata, while request construction and transport behavior stay in
  the runtime.
  """

  alias MetaAds.Client

  @doc """
  Creates a client.

  Required: `:access_token`. Optional: `:app_secret`, `:api_version`,
  `:endpoint`, `:http_client`, and `:timeout`. Direct loopback transport tests
  may also set `:allow_insecure_localhost`; applications should use HTTPS.

  ## Examples

      {:ok, client} = MetaAds.client(access_token: "token")

  """
  @spec client(keyword() | map()) :: {:ok, Client.t()} | {:error, MetaAds.Error.t()}
  def client(attrs \\ []) do
    Client.new(attrs)
  end
end
