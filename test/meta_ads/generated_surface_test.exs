defmodule MetaAds.GeneratedSurfaceTest do
  use ExUnit.Case, async: true

  alias MetaAds.Models.{AdAccount, AdCreative, AdSet, Campaign}

  test "covers the core Ads object surface" do
    for module <- [AdAccount, Campaign, AdSet, AdCreative] do
      assert Enum.any?(module.fields(), &(&1["name"] == "id"))
    end

    expected_operations = [
      {AdAccount, :get_campaigns},
      {AdAccount, :create_campaigns},
      {Campaign, :get},
      {Campaign, :create},
      {AdSet, :get},
      {AdCreative, :get}
    ]

    for {module, operation} <- expected_operations do
      assert {operation, 2} in module.module_info(:functions)
    end
  end

  test "retains enum metadata for generated parameters" do
    operation = Enum.find(Campaign.operations(), &(&1["function"] == "get"))
    parameter = Enum.find(operation["params"], &(&1["name"] == "date_preset"))

    assert parameter["values"]
    assert "today" in parameter["values"]
  end

  test "builds every pinned basePath operation as base path followed by object ID" do
    alias MetaAds.Models.{AdCampaignPlacement, IntegrityAppeal}

    {:ok, client} =
      MetaAds.client(
        access_token: "token",
        endpoint: "https://graph.test",
        http_client: MetaAds.TestRecordingHTTP
      )

    placement_params = %{
      "account_id" => "act_1",
      "billing_event" => "IMPRESSIONS",
      "buying_type" => "AUCTION",
      "objective" => "OUTCOME_TRAFFIC",
      "optimization_goal" => "LINK_CLICKS"
    }

    cases = [
      {AdCampaignPlacement, :get, placement_params, "/v26.0/ad_campaign_placement/object%2F123"},
      {IntegrityAppeal, :get_ad_appeal_bulk_eligibility, %{"ad_ids" => [1]},
       "/v26.0/integrity/appeals/ads/eligibility/object%2F123"},
      {IntegrityAppeal, :get_ad_appeal_bulk_status, %{"ad_ids" => [1]},
       "/v26.0/integrity/appeals/ads/status/object%2F123"},
      {IntegrityAppeal, :get_eligibility, %{}, "/v26.0/integrity/appeals/ads/object%2F123"},
      {IntegrityAppeal, :get_status, %{}, "/v26.0/integrity/appeals/ads/object%2F123"},
      {IntegrityAppeal, :create_ad_appeal_bulk, %{}, "/v26.0/integrity/appeals/ads/object%2F123"}
    ]

    for {module, function, params, expected_path} <- cases do
      assert {:ok, %MetaAds.Response{}} =
               apply(module, function, [client, "object/123", params])

      assert_received {:http_request, _method, url, _headers, _body, _options}
      assert URI.parse(url).path == expected_path
    end
  end

  test "does not expose operations that require multipart file parameters" do
    {:ok, modules} = :application.get_key(:meta_ads, :modules)

    operations =
      modules
      |> Enum.filter(&(Module.split(&1) |> Enum.take(2) == ["MetaAds", "Models"]))
      |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :operations, 0)))
      |> Enum.flat_map(& &1.operations())

    assert length(operations) == 1461

    refute Enum.any?(operations, fn operation ->
             Enum.any?(operation["params"], &file_param?/1)
           end)

    refute function_exported?(AdAccount, :create_block_list_drafts, 2)
    refute function_exported?(MetaAds.Models.Business, :create_self_certify_whatsapp_business, 3)
  end

  defp file_param?(%{"type" => type}), do: type == "file" or type == "list<file>"
end
