defmodule MetaAds.HTTP.HttpcTest do
  use ExUnit.Case, async: true

  alias MetaAds.HTTP.Httpc
  alias MetaAds.TestLocalHTTPServer

  test "executes GET requests through the production adapter" do
    {endpoint, server} =
      TestLocalHTTPServer.serve_once(
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 11\r\n\r\n{\"ok\":true}"
      )

    assert {:ok, %MetaAds.Response{status: 200, body: %{"ok" => true}}} =
             Httpc.request(:get, endpoint <> "/health?ready=true", [], nil, timeout: 500)

    request = TestLocalHTTPServer.await_request(server)
    assert request =~ "GET /health?ready=true HTTP/1.1"
  end

  test "executes form POST requests with an explicit content type" do
    {endpoint, server} =
      TestLocalHTTPServer.serve_once(
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 10\r\n\r\n{\"id\":\"1\"}"
      )

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    assert {:ok, %MetaAds.Response{status: 200}} =
             Httpc.request(:post, endpoint <> "/campaigns", headers, "name=A+B", timeout: 500)

    request = TestLocalHTTPServer.await_request(server)
    assert request =~ "POST /campaigns HTTP/1.1"
    assert request =~ "content-type: application/x-www-form-urlencoded"
    assert request =~ "name=A+B"
  end

  test "the default client returns redirects without forwarding bearer credentials" do
    {endpoint, server} =
      TestLocalHTTPServer.serve_once(
        "HTTP/1.1 302 Found\r\nlocation: http://127.0.0.1:1/capture\r\ncontent-length: 0\r\n\r\n"
      )

    assert {:ok, client} =
             MetaAds.client(
               access_token: "secret",
               endpoint: endpoint,
               allow_insecure_localhost: true,
               timeout: 500
             )

    assert {:error, %MetaAds.Error{status: 302}} =
             MetaAds.Client.request(client, :get, "/redirect")

    request = TestLocalHTTPServer.await_request(server)
    assert request =~ "authorization: Bearer secret"
  end
end
