defmodule MetaAds.ResponseTest do
  use ExUnit.Case, async: true

  alias MetaAds.Response

  test "unwraps edge data while retaining pagination" do
    {:ok, response} =
      Response.new(
        200,
        [],
        ~s({"data":[{"id":"1"}],"paging":{"cursors":{"after":"a"}}})
      )

    assert Response.data(response) == [%{"id" => "1"}]
    assert Response.paging(response)["cursors"]["after"] == "a"
    assert Response.next_page_url(response) == nil
  end

  test "decodes Graph errors" do
    {:ok, response} =
      Response.new(
        400,
        [],
        ~s({"error":{"message":"Invalid","code":100,"type":"OAuthException"}})
      )

    error = MetaAds.Error.from_response(response)
    assert error.status == 400
    assert error.code == 100
    assert error.type == "OAuthException"
    assert error.message == "Invalid"
  end
end
