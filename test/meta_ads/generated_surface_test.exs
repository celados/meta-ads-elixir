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
end
