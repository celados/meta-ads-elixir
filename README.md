# Meta Ads SDK for Elixir

`meta_ads` is an Elixir SDK for the Meta Marketing API. It provides a small runtime client and a generated model surface based on Meta's public Business SDK JSON schema.

## Installation

The package is not published to Hex yet. Use the Git dependency after the repository is available:

```elixir
def deps do
  [
    {:meta_ads, git: "https://github.com/ethan-huo/meta-ads-elixir.git", tag: "v0.1.0"}
  ]
end
```

## Usage

```elixir
alias MetaAds.Models.AdAccount

{:ok, client} =
  MetaAds.client(
    access_token: System.fetch_env!("META_ACCESS_TOKEN"),
    app_secret: System.fetch_env!("META_APP_SECRET")
  )

with {:ok, page} <-
       AdAccount.get_campaigns(client, "act_123", %{
         "fields" => ["id", "name", "status"],
         "limit" => 50
       }) do
  page
  |> MetaAds.Response.data()
  |> Enum.map(&{&1["id"], &1["name"]})
end
```

Operations return the decoded Graph API envelope in `MetaAds.Response`. `MetaAds.Response.data/1` unwraps edge `data`, while paging metadata remains available:

```elixir
case MetaAds.Client.follow(client, page) do
  {:ok, next_page} -> MetaAds.Response.data(next_page)
  {:error, error} -> {:error, error}
end
```

Required parameters and known enum values are validated before an HTTP request is made. Unknown parameters are passed through because Meta can expose undocumented fields and parameters.

## HTTP transport

The default adapter uses Erlang's built-in `:httpc`; the SDK has no runtime Hex dependencies. Pass a custom module to use Finch, Req, Tesla, or an application-specific transport:

```elixir
defmodule MyApp.MetaHTTP do
  @behaviour MetaAds.HTTP

  @impl MetaAds.HTTP
  def request(method, url, headers, body, options) do
    # delegate to your preferred HTTP client and return
    # {:ok, MetaAds.Response.t()} | {:error, term()}
  end
end

{:ok, client} = MetaAds.client(access_token: token, http_client: MyApp.MetaHTTP)
```

## Generated surface

The generated surface currently contains 1,074 model modules and 1,489 operations. It includes the core Ads hierarchy—`AdAccount`, `Campaign`, `AdSet`, `Ad`, `AdCreative`, and `AdsInsights`—as well as the other Graph objects in Meta's schema snapshot.

Regenerate after changing the vendored schema:

```sh
mix meta_ads.generate
mix test
```

The source snapshot and commit are recorded in [`priv/codegen/SOURCE.json`](priv/codegen/SOURCE.json).

## Status and boundaries

- This is not an official Meta SDK.
- Responses intentionally preserve Graph's raw JSON envelope rather than guessing struct coercion for every field.
- Cursor pagination is supported through `MetaAds.Client.follow/3`; automatic streams are not implemented yet.
- Multipart file upload is not implemented yet.
- One schema operation, `AdsSubscription` delete with `subscriptions/{Dynamic}`, is intentionally skipped because it needs explicit dynamic path modeling.

See [docs/architecture.md](docs/architecture.md) for the SDK design and update workflow.
