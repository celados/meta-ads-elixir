---
type: Reference
title: Meta Ads Elixir SDK architecture
description: Runtime, generated model surface, schema provenance, and maintenance workflow for the meta_ads package.
status: draft
version: 0.2
generated:
  by: codex/gpt-5
  at: 2026-08-30T17:00:03+08:00
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
| `MetaAds.Client` | `request/5`, `follow/3`, `path/4` | Versioned Graph URL construction, HTTP execution, app secret proof, shared response classification, and cursor safety. |
| `MetaAds.Config` | internal | Validates credentials and converts an origin-only HTTPS endpoint into trusted configuration. |
| `MetaAds.Params` | internal | Required-parameter checks, enum checks, atom-key normalization, and Graph complex-value encoding. |
| `MetaAds.Response` | `new/3`, `data/1`, `paging/1`, `next_page_url/1` | Preserves the Graph envelope and provides common node/edge access. |
| `MetaAds.Error` | exception | Normalizes validation, transport, and Graph error envelopes while retaining Meta's details. |
| `MetaAds.HTTP` | callback | The transport seam for custom HTTP adapters. |
| `MetaAds.Models.*` | generated functions | Model field metadata and Graph operation functions. |
| `Mix.Tasks.MetaAds.Generate` | `mix meta_ads.generate` | Verifies the local manifest and turns the pinned JSON schema snapshot into model modules. |
| `Mix.Tasks.MetaAds.VerifySnapshot` | `mix meta_ads.verify_snapshot` | Verifies every vendored byte against the manifest and reachable upstream commit. |

## Request lifecycle

1. A generated function validates required parameters and known enum values.
2. The model asks `MetaAds.Client` to construct either an ordinary `node/edge` path or the schema's distinct `basePath/node` path.
3. The client adds bearer authentication and, when configured, the lowercase-hex HMAC-SHA256 `appsecret_proof`.
4. Lists and objects are encoded as JSON strings; field lists use Graph's comma-separated convention.
5. GET and DELETE parameters are placed in the query string; POST and PUT parameters are form-encoded with an explicit content type.
6. The built-in adapter retains OTP TLS verification and returns redirects without following them.
7. One shared classifier turns non-2xx responses and Graph `error` envelopes into `MetaAds.Error`, retaining raw body and headers.

The HTTP seam is real rather than hypothetical: tests use an in-memory adapter and production uses `:httpc` through the same callback.

## Generated surface

The pinned snapshot is Meta's reachable `facebook-business-sdk-codegen` commit `601cf8f4ad71d19018ca277f7d77318e77e0b072`, captured on 2026-08-30. The generated output currently has:

- 1,074 model modules.
- 1,461 operations.
- Twenty-eight omitted multipart operations whose schema contains a `file` or `list<file>` parameter.
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

1. Replace `priv/codegen/specs` from one exact upstream `api_specs/specs` directory, including `version.txt`.
2. Update `priv/codegen/SOURCE.json` with the exact repository commit and capture time.
3. Run `mix meta_ads.verify_snapshot --update-manifest`; it verifies the upstream archive before rewriting `MANIFEST.sha256`.
4. Run `mix meta_ads.verify_snapshot` and `mix meta_ads.generate`.
5. Run `mix format`.
6. Run `mix compile --warnings-as-errors && mix test`.
7. Review the diff before committing; do not publish a schema upgrade merely because generation succeeded.

The snapshot is vendored intentionally. Generation fails on local manifest drift, while the explicit verification task also fails on an unreachable ref or any upstream byte difference. Package compilation remains network-independent.

## Current non-goals

- No automatic retry or rate-limit scheduling; applications should choose policy at their transport adapter.
- No automatic pagination stream yet; `Client.follow/3` provides the building block.
- No multipart upload helper yet; file-bearing operations are not generated until that transport seam exists.
- No OAuth client; the SDK accepts an already acquired access token.

## Verification

- `mix compile --warnings-as-errors`
- `mix test`
- `mix meta_ads.verify_snapshot`
- `mix meta_ads.generate`

Tests cover the production `:httpc` adapter against a local TCP server, redirect refusal, generated request construction, form and query encoding, required and enum validation, error decoding and raw diagnostics, positive and hostile pagination, all six `basePath` operations, snapshot-manifest validation, multipart omission, config validation, and core generated Ads modules.

## Package licensing

The Hex file set is explicit. Project-authored code and documentation carry MIT; vendored Meta schema and generated material derived from it carry the included Facebook Platform license notice in `LICENSE.meta-codegen`. Package metadata names both without asserting broader legal compatibility.
