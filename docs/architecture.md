---
type: Reference
title: Meta Ads Elixir SDK architecture
description: Runtime, generated model surface, schema provenance, and maintenance workflow for the meta_ads package.
status: draft
version: 0.1
generated:
  by: codex/gpt-5
  at: 2026-08-30T15:40:00+08:00
---

# Meta Ads Elixir SDK architecture

## Decision

`meta_ads` is organized as an SDK first and a code generator second. The code generator is not the runtime: it emits metadata and operation functions, while authentication, request encoding, validation, pagination, errors, and HTTP execution live in one runtime implementation.

This gives the package two useful properties:

- Callers learn a small interface: `MetaAds.client/1`, generated model functions, and `MetaAds.Response`.
- Schema updates change generated metadata and operation names without copying HTTP behavior into more than one thousand modules.

## Module map

| Module | Interface | Responsibility |
| --- | --- | --- |
| `MetaAds` | `client/1` | Package entrypoint and client construction. |
| `MetaAds.Client` | `request/5`, `follow/3`, `path/4` | Versioned Graph URL construction, HTTP execution, app secret proof, response classification, and cursor safety. |
| `MetaAds.Config` | internal | Validates credentials and escape hatches. |
| `MetaAds.Params` | internal | Required-parameter checks, enum checks, atom-key normalization, and Graph complex-value encoding. |
| `MetaAds.Response` | `new/3`, `data/1`, `paging/1`, `next_page_url/1` | Preserves the Graph envelope and provides common node/edge access. |
| `MetaAds.Error` | exception | Normalizes validation, transport, and Graph error envelopes while retaining Meta's details. |
| `MetaAds.HTTP` | callback | The transport seam for custom HTTP adapters. |
| `MetaAds.Models.*` | generated functions | Model field metadata and Graph operation functions. |
| `Mix.Tasks.MetaAds.Generate` | `mix meta_ads.generate` | Turns the pinned JSON schema snapshot into model modules. |

## Request lifecycle

1. A generated function validates required parameters and known enum values.
2. The model asks `MetaAds.Client` to construct the versioned object path.
3. The client adds bearer authentication and, when configured, the lowercase-hex HMAC-SHA256 `appsecret_proof`.
4. Lists and objects are encoded as JSON strings; field lists use Graph's comma-separated convention.
5. GET and DELETE parameters are placed in the query string; POST and PUT parameters are form-encoded.
6. The HTTP adapter returns `MetaAds.Response`; non-2xx responses and Graph error envelopes become `MetaAds.Error`.

The HTTP seam is real rather than hypothetical: tests use an in-memory adapter and production uses `:httpc` through the same callback.

## Generated surface

The pinned snapshot is Meta's `facebook-business-sdk-codegen` commit `601cf8f4ad71d19018ca277f7d77318e77c0b072`, captured on 2026-08-30. The generated output currently has:

- 1,074 model modules.
- 1,489 operations.
- One skipped dynamic endpoint: `AdsSubscription` delete at `subscriptions/{Dynamic}`.

Generated modules call the `field/3`, `operation/5`, and `finish/0` macros from `MetaAds.Model`. Each operation carries:

- generated function name
- Graph HTTP method
- endpoint
- optional base path
- parameter names, required flags, types, and enum values

Fields carry their API name, schema type, and enum values when the official schema defines them.

## Why responses stay as Graph envelopes

The SDK deliberately returns decoded Graph envelopes instead of coercing every response into a struct. Graph fields can be conditionally present, polymorphic, or version-specific; coercion at this layer would hide data and require SDK releases for harmless upstream additions. `MetaAds.Response.data/1` still normalizes the common node-versus-edge difference, and generated field metadata remains available for application-side coercion.

## Schema update workflow

1. Replace the JSON files in `priv/codegen/specs`.
2. Update `priv/codegen/SOURCE.json` with the exact repository commit and capture time.
3. Run `mix meta_ads.generate`.
4. Run `mix format`.
5. Run `mix compile --warnings-as-errors && mix test`.
6. Review the diff before committing; do not publish a schema upgrade merely because generation succeeded.

The snapshot is vendored intentionally. Package compilation must be reproducible, and an upstream repository move or history rewrite must not change a package release.

## Current non-goals

- No automatic retry or rate-limit scheduling; applications should choose policy at their transport adapter.
- No automatic pagination stream yet; `Client.follow/3` provides the building block.
- No multipart upload helper yet.
- No OAuth client; the SDK accepts an already acquired access token.

## Verification

- `mix compile --warnings-as-errors`
- `mix test`

Tests cover generated request construction, form and query encoding, required and enum validation, error decoding, pagination safety, config validation, and core generated Ads modules.
