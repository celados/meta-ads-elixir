defmodule MetaAds.ConfigTest do
  use ExUnit.Case, async: true

  test "requires a non-empty access token" do
    assert {:error, error} = MetaAds.client(access_token: " ")
    assert error.field == "access_token"
  end

  test "rejects unsafe escape hatches" do
    assert {:error, _} = MetaAds.client(access_token: "token", api_version: "../v26.0")
    assert {:error, _} = MetaAds.client(access_token: "token", endpoint: "not-a-url")
    assert {:error, _} = MetaAds.client(access_token: "token", timeout: 0)
    assert {:error, _} = MetaAds.client(access_token: "token", http_client: String)
  end

  test "requires an origin-only HTTPS endpoint" do
    assert {:error, _} = MetaAds.client(access_token: "token", endpoint: "http://graph.test")

    assert {:error, _} =
             MetaAds.client(access_token: "token", endpoint: "https://graph.test/path")

    assert {:error, _} = MetaAds.client(access_token: "token", endpoint: "https://graph.test?q=1")

    assert {:error, _} =
             MetaAds.client(access_token: "token", endpoint: "https://token@graph.test")

    assert {:ok, client} = MetaAds.client(access_token: "token", endpoint: "https://graph.test/")
    assert client.config.endpoint == "https://graph.test"
  end

  test "allows cleartext HTTP only for an explicitly enabled loopback endpoint" do
    assert {:ok, _client} =
             MetaAds.client(
               access_token: "token",
               endpoint: "http://127.0.0.1:4000",
               allow_insecure_localhost: true
             )

    assert {:error, _} =
             MetaAds.client(
               access_token: "token",
               endpoint: "http://graph.test",
               allow_insecure_localhost: true
             )
  end
end
