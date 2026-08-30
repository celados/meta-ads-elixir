defmodule MetaAds.ClientTest do
  use ExUnit.Case, async: true

  alias MetaAds.Models.AdAccount
  alias MetaAds.TestRecordingHTTP

  test "generated GET operations build a versioned Graph request with proof and encoded params" do
    {:ok, client} =
      MetaAds.client(
        access_token: "token",
        app_secret: "secret",
        endpoint: "https://graph.test",
        http_client: TestRecordingHTTP,
        timeout: 1234
      )

    params = %{
      "effective_status" => ["ACTIVE"],
      "time_range" => %{"since" => "2026-01-01", "until" => "2026-01-31"}
    }

    assert {:ok, %MetaAds.Response{} = response} =
             AdAccount.get_campaigns(client, "act/123", params, response_body: "{}")

    assert_received {:http_request, :get, url, headers, nil, options}
    assert URI.parse(url).path == "/v26.0/act%2F123/campaigns"
    assert List.keyfind(headers, "authorization", 0) == {"authorization", "Bearer token"}
    assert options[:timeout] == 1234

    query = URI.decode_query(URI.parse(url).query)
    proof = Base.encode16(:crypto.mac(:hmac, :sha256, "secret", "token"), case: :lower)
    assert query["appsecret_proof"] == proof
    assert query["effective_status"] == ~s(["ACTIVE"])
    assert query["time_range"] == ~s({"since":"2026-01-01","until":"2026-01-31"})
    assert MetaAds.Response.data(response) == %{}
  end

  test "generated POST operations encode required and complex parameters as form data" do
    {:ok, client} =
      MetaAds.client(
        access_token: "token",
        app_secret: "secret",
        endpoint: "https://graph.test",
        http_client: TestRecordingHTTP,
        response_body: ~s({"id":"123"})
      )

    assert {:ok, _response} =
             AdAccount.create_campaigns(client, "act_123", %{
               "name" => "Test campaign",
               "special_ad_categories" => ["NONE"]
             })

    assert_received {:http_request, :post, "https://graph.test/v26.0/act_123/campaigns", _headers,
                     body, _options}

    decoded = URI.decode_query(body)
    proof = Base.encode16(:crypto.mac(:hmac, :sha256, "secret", "token"), case: :lower)
    assert decoded["name"] == "Test campaign"
    assert decoded["special_ad_categories"] == ~s(["NONE"])
    assert decoded["appsecret_proof"] == proof
  end

  test "validation failures never reach the HTTP transport" do
    {:ok, client} = MetaAds.client(access_token: "token", http_client: TestRecordingHTTP)

    assert {:error, error} =
             AdAccount.create_campaigns(client, "act_123", %{"name" => "Missing required"})

    assert error.field == "params"
    assert error.message =~ "special_ad_categories"
    refute_received {:http_request, _, _, _, _, _}

    assert {:error, error} =
             MetaAds.Models.Campaign.get(client, "123", %{"date_preset" => "NOT_A_PRESET"})

    assert error.field == "params.date_preset"
    assert error.message =~ "NOT_A_PRESET"
    refute_received {:http_request, _, _, _, _, _}
  end

  test "follow only accepts paging URLs on the configured endpoint" do
    {:ok, client} =
      MetaAds.client(
        access_token: "token",
        endpoint: "https://graph.test",
        http_client: TestRecordingHTTP,
        response_body: ~s({"paging":{"next":"https://evil.test/next"}})
      )

    assert {:ok, response} =
             AdAccount.get_campaigns(client, "act_123", %{},
               response_body: ~s({"paging":{"next":"https://evil.test/next"}})
             )

    assert {:error, error} = MetaAds.Client.follow(client, response)
    assert error.field == "paging.next"
    refute_received {:http_request, :get, "https://evil.test/next", _, _, _}
  end
end
