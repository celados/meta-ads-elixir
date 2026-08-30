defmodule MetaAds.TestRecordingHTTP do
  @moduledoc false
  @behaviour MetaAds.HTTP

  alias MetaAds.Response

  @impl MetaAds.HTTP
  def request(method, url, headers, body, options) do
    send(self(), {:http_request, method, url, headers, body, options})

    body =
      if options[:response_body] do
        options[:response_body]
      else
        ~s({"data":[{"id":"1","name":"Campaign"}],"paging":{"next":"https://graph.facebook.com/v26.0/next"}})
      end

    Response.new(200, [{"content-type", "application/json"}], body)
  end
end
