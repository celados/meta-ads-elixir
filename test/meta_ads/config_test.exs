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
  end
end
