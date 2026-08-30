defmodule MetaAds.HTTP do
  @moduledoc """
  Transport seam used by `MetaAds.Client`.

  Tests and applications can replace `:http_client` with any module that
  implements this callback; the SDK's request construction stays independent of
  the HTTP adapter. POST and PUT bodies are URL-encoded and carry an explicit
  `content-type` header.
  """

  alias MetaAds.Response

  @callback request(atom(), String.t(), list(), binary() | nil, keyword()) ::
              {:ok, Response.t()} | {:error, term()}
end
