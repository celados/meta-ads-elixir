---
type: Review
title: Independent Codex review of meta_ads v0.1.0
description: Falsifiable review of the SDK runtime, generated surface, tests, provenance, and public release readiness.
resource: ./2026-08-30-codex-review.workorder.md
verdict: request-changes
review_target: 206eaf8e41b9d627a78abb8ece44f930f5a07e7c
generated:
  by: codex/gpt-5
  at: 2026-08-30T16:19:17+08:00
---

# Independent Codex review of meta_ads v0.1.0

## Verdict

`request-changes`

The runtime/generator split is directionally sound, normal GET/POST parameter encoding and `appsecret_proof` are correct, hostile pagination URLs are rejected, and regeneration is currently idempotent. The public `v0.1.0` is nevertheless not releasable: its default HTTP adapter cannot execute a request, transport defaults are unsafe or unusable, all six `basePath` operations build the wrong path, some Graph errors are returned as success, file-upload operations are exposed without a transport representation, and the recorded upstream commit is invalid. Hex license metadata also needs resolution before publication.

The checked-out `HEAD` and annotated target were independently verified:

```text
$ git rev-parse HEAD
206eaf8e41b9d627a78abb8ece44f930f5a07e7c
$ git rev-parse 'v0.1.0^{}'
206eaf8e41b9d627a78abb8ece44f930f5a07e7c
```

## Review-question summary

| Area | Conclusion |
| --- | --- |
| SDK interface | The small entrypoint and centralized runtime are coherent, but generated functions expose unsupported upload operations and noisy names such as `get_get_*`. |
| Correctness | Bearer auth, HMAC-SHA256 proof, ordinary query/form encoding, enum rejection, and object-ID escaping are sound. Default transport, `basePath`, 2xx error-envelope handling, required-value validation, and positive pagination behavior are not. |
| Generated surface | The current snapshot regenerates to 1,074 modules and 1,489 operations with no current module/function-name collisions. It loses return metadata, has no collision preflight, and can leave a partial output tree on failure. |
| Runtime design | `Client`, `Params`, `Response`, `Error`, and `HTTP` are mostly at useful seams. Response classification is duplicated, the custom HTTP contract omits the body media type, and `Model.request/9` carries an unused model argument. |
| Security | `follow/3` rejects an explicitly hostile paging host. In contrast, endpoint configuration permits cleartext HTTP and the default adapter inherits cross-origin redirects while carrying the Bearer header. |
| Tests | Ten tests pass but all HTTP tests replace the production adapter. Production-critical transport, `basePath`, uploads, 2xx errors, positive pagination, and generator failure paths are untested. |
| Release readiness | Blocked by S1-S7 below. S8-S12 should also be addressed or explicitly narrowed before declaring the corresponding public behavior supported. |

## Spec findings

### S1 — Critical — The default HTTP adapter cannot execute any request

- **Evidence:** `lib/meta_ads/http/httpc.ex:9-26` builds `{method, url, headers, content_type, body}` and supplies it as the first argument to `:httpc.request/2`. OTP interprets that arity differently. A request through the package's default client failed before connecting:

  ```text
  $ mix run --no-compile -e '<construct default client; request /v26.0/me>'
  ** (FunctionClauseError) no function clause matching in :httpc.request/5
  (meta_ads 0.1.0) lib/meta_ads/http/httpc.ex:26
  (meta_ads 0.1.0) lib/meta_ads/client.ex:51
  ```

  `test/support/recording_http.ex:1-20` replaces the adapter in every request-construction test, so `mix test` cannot detect this.
- **Impact:** The README's dependency and default-client path cannot make even one Graph request. The advertised zero-dependency production transport is nonfunctional.
- **Confidence:** High; reproduced through the public client at the review target.
- **Minimal recommended fix:** Use the documented `:httpc.request/4` contract with method-specific request tuples (`{url, headers}` for GET/DELETE and `{url, headers, content_type, body}` for POST/PUT), return transport errors without double wrapping, and add direct adapter tests for one query request, one form request, and one network error.

### S2 — Critical — Credential transport policy is unsafe and the TLS override is unusable

- **Evidence:** `lib/meta_ads/config.ex:76-83` accepts both `http` and `https`, including non-origin endpoint forms with paths or queries. `lib/meta_ads/client.ex:109-113` always attaches `Authorization: Bearer ...`. `lib/meta_ads/http/httpc.ex:20-24` explicitly supplies `ssl: []` and does not disable `:httpc`'s default automatic redirects.

  On the reviewed OTP 28.4 runtime, a correctly shaped direct `:httpc` request with the adapter's SSL option failed deterministically:

  ```text
  {:error, {:failed_connect, [...,
    {:options, :incompatible, [verify: :verify_peer, cacerts: :undefined]}]}}
  ```

  OTP 28.4 documents `autoredirect` as defaulting to `true`; its redirect implementation retains the request headers while changing the destination host. This bypasses the explicit same-endpoint check in `Client.follow/3`. A separate focused check also showed that `MetaAds.client(access_token: "token", endpoint: "http://graph.facebook.com")` returns `{:ok, client}`.
- **Impact:** After S1 is fixed, HTTPS still fails on the reviewed runtime. Allowing cleartext endpoints can expose access tokens, and an HTTP 30x response can forward the Bearer header to another origin.
- **Confidence:** High for the reviewed OTP/runtime and source; the redirect risk follows directly from the enabled OTP behavior.
- **Minimal recommended fix:** Require an origin-only HTTPS endpoint by default; make any localhost HTTP escape hatch explicit. Do not pass an empty SSL option—retain `:httpc`'s verified-host defaults or supply equivalent CA/hostname verification. Disable automatic redirects and handle any permitted redirect with the same canonical-origin policy as pagination.

### S3 — High — All six `basePath` operations construct a different URL from the source schema

- **Evidence:** `lib/meta_ads/client.ex:76-83` always orders path segments as `api_version/object_id/base_path/edge`. `lib/meta_ads/models/integrity_appeal.ex:5-15` contains five `basePath` operations, and `lib/meta_ads/models/ad_campaign_placement.ex:5-15` contains the sixth. A focused public call produced:

  ```text
  "/v26.0/object-123/integrity/appeals/ads/eligibility"
  ```

  The source schema records `basePath: "integrity/appeals/ads"` for this operation. Meta's pinned Python `FacebookRequest` template models a base-path request as `(base_path, node_id)`, rather than placing `base_path` after the node and then appending `endpoint`: [upstream request template](https://github.com/facebook/facebook-business-sdk-codegen/blob/601cf8f4ad71d19018ca277f7d77318e77e0b072/templates/python/facebook_business/api.py).
- **Impact:** These six generated public functions request nonexistent or semantically different Graph paths.
- **Confidence:** High; local metadata, generated source, runtime output, and upstream request semantics agree.
- **Minimal recommended fix:** Give `Client.path/4` an explicit base-path branch matching `base_path/node_id`; do not append the ordinary edge in that branch. Add golden URL tests for each of the six current operations.

### S4 — High — A Graph error envelope with a 2xx status is returned as success

- **Evidence:** `lib/meta_ads/client.ex:51-54` and `:86-90` classify only by HTTP status. A focused adapter returning status 200 with `{"error":{"message":"Invalid","code":100}}` produced:

  ```text
  {:ok, %MetaAds.Response{status: 200,
    body: %{"error" => %{"code" => 100, "message" => "Invalid"}}}}
  ```

  This contradicts `docs/architecture.md:44`, which says Graph error envelopes become `MetaAds.Error`. Meta's upstream SDK likewise checks for an `error` key independently of status in `FacebookResponse.is_success/1` at the source linked in S3.
- **Impact:** Callers can persist, bill on, or paginate from a failed Graph operation as though it succeeded.
- **Confidence:** High; reproduced through `Client.request/5`.
- **Minimal recommended fix:** Centralize response classification and reject a valid Graph `error` envelope before accepting a 2xx status. Preserve the complete response in the resulting error.

### S5 — High — Twenty-seven generated upload operations are public but cannot represent a file upload

- **Evidence:** A schema scan found 27 operations with a `file` parameter, including four required file parameters. For example, `lib/meta_ads/models/ad_account.ex:1726-1728` exposes `create_block_list_drafts/4` with required `publisher_urls_file`. `lib/meta_ads/params.ex:25-38` converts that value to a string and `lib/meta_ads/client.ex:94-96` form-encodes it; neither `MetaAds.HTTP` nor `Client` carries multipart parts. README lines 86-87 admit multipart is not implemented but do not remove or reject these generated operations.
- **Impact:** These functions appear supported, validate successfully, and then send a file path/value as ordinary form text. Four cannot succeed without an undocumented out-of-band adapter contract; the remaining 23 silently lose upload semantics when callers supply a file.
- **Confidence:** High; the schema count and runtime encoding path are deterministic.
- **Minimal recommended fix:** For v0.1, omit operations containing `type: "file"` or return an explicit unsupported-operation error before transport. Only generate them once the HTTP behavior has a typed multipart representation and tests exercise it.

### S6 — High — The recorded upstream commit does not exist

- **Evidence:** `priv/codegen/SOURCE.json:2-5` records `601cf8f4ad71d19018ca277f7d77318e77c0b072`. GitHub rejects that ref. The public repository currently resolves HEAD as the one-character-different SHA:

  ```text
  $ git ls-remote https://github.com/facebook/facebook-business-sdk-codegen.git HEAD
  601cf8f4ad71d19018ca277f7d77318e77e0b072  HEAD
  ```

  Reading the corrected commit's `IntegrityAppeal.json` reproduces the local schema fragment; that is evidence of a likely transcription error, not proof that every vendored file matches.
- **Impact:** The package's provenance and documented reproducibility claim (`docs/architecture.md:50,72-79`) are false as written. Reviewers cannot reconstruct or audit the complete snapshot from the recorded source.
- **Confidence:** High that the recorded ref is invalid; medium that changing only that character is sufficient without a full-tree comparison.
- **Minimal recommended fix:** Compare every vendored source file with the reachable commit, then record the verified SHA and a deterministic tree/hash manifest. Fail release validation when the source ref cannot be fetched.

### S7 — High — Hex metadata declares only MIT while the package includes separately licensed Meta material

- **Evidence:** `mix.exs:34-39` declares `licenses: ["MIT"]`. `LICENSE.meta-codegen:1-18` grants a separate license limited to use with Facebook services/APIs. `mix help hex.build` confirms that Hex's default file set includes both `priv` and `LICENSE*`, so the vendored specs and both license files enter the package.
- **Impact:** The published Hex metadata would describe the package as MIT-only even though its contents carry another license and usage conditions. This is a release/legal metadata mismatch; this review does not assert a legal conclusion about compatibility.
- **Confidence:** High on package contents and metadata; legal disposition requires maintainer or counsel confirmation.
- **Minimal recommended fix:** Before publishing, explicitly define the package file set, verify the provenance/license obligations for specs and derived generated modules, and make Hex license metadata/documentation accurately describe every included license.

### S8 — Medium — A required parameter is considered present when its value is `nil`

- **Evidence:** `lib/meta_ads/params.ex:49-60` checks only `Map.has_key?/2`; `:25-38` later stringifies unhandled values. Using the required `list<int>` parameter from `IntegrityAppeal` produced:

  ```text
  %{"ad_ids" => ""}
  ```

  rather than a validation error.
- **Impact:** The SDK's promised preflight validation lets invalid required values reach Graph, adding latency and replacing a precise local error with a remote one.
- **Confidence:** High; reproduced against the production functions.
- **Minimal recommended fix:** Define presence by schema type and reject `nil` (plus empty values where the schema requires a value) before enum/encoding steps.

### S9 — Medium — The custom HTTP contract omits the media type of its form body

- **Evidence:** `lib/meta_ads/client.ex:94-96` produces a URL-encoded body for POST/PUT, but `:109-113` supplies only Authorization and Accept headers. A focused custom adapter received:

  ```text
  {[{"authorization", "Bearer token"}, {"accept", "application/json"}],
   "name=A+B"}
  ```

  `MetaAds.HTTP.Httpc` privately invents a default content type at `lib/meta_ads/http/httpc.ex:35-39`; other implementations of the advertised `MetaAds.HTTP` behavior cannot learn that rule from the request.
- **Impact:** A conforming custom adapter can send a syntactically valid body without the required `application/x-www-form-urlencoded` declaration, producing server-dependent failures.
- **Confidence:** High.
- **Minimal recommended fix:** Make content type part of the runtime request contract—preferably an explicit header created beside body encoding—and test it through a non-`:httpc` adapter.

### S10 — Medium — Pagination drops the configured timeout

- **Evidence:** Ordinary requests add `client.config.timeout` at `lib/meta_ads/client.ex:46-50`, while `call_next/3` passes caller options unchanged at `:86-90`. With a client timeout of 1234, a safe positive pagination request delivered `follow_options: []` to the adapter.
- **Impact:** `follow/3` violates client configuration and can wait according to an adapter-specific default. The current test covers only hostile-host rejection, never a successful follow.
- **Confidence:** High; reproduced with the public pagination function.
- **Minimal recommended fix:** Route initial and follow-up requests through one option/default and response-classification function.

### S11 — Medium — Non-JSON HTTP errors lose the response body and headers

- **Evidence:** `lib/meta_ads/error.ex:32-44` retains only the nested JSON `error` map. When `Response.body` is text or a non-Graph map, `details` becomes `%{}`; `MetaAds.Error` has no response-body or response-header field.
- **Impact:** Proxy errors, HTML gateway failures, and malformed Graph responses erase the most useful production diagnostic data.
- **Confidence:** High from exhaustive clauses in `Error.from_response/1`.
- **Minimal recommended fix:** Retain the original normalized response (or at least raw body and headers) on every HTTP error, while keeping the convenience Graph fields.

### S12 — Medium — Generation is destructive before validation and omits collision/return checks

- **Evidence:** `lib/mix/tasks/meta_ads.generate.ex:46-55` deletes the entire output directory before it has parsed all specs, then writes one model at a time through `:98-147`. Module names (`:99-102`) and function names (`:168-191`) are normalized without a preflight uniqueness check. A read-only scan found no collision in this snapshot and exact counts of 1,074 spec/model files and 1,489 generated operations. The source's `return` key exists on all 1,490 API records, but `MetaAds.Model` operation metadata at `lib/meta_ads/model.ex:28-34` omits it.
- **Impact:** A malformed future spec leaves a partial generated tree; a future normalization collision can overwrite or ambiguously define public code; consumers of `__schema__/0` cannot discover the declared response type.
- **Confidence:** High for the failure ordering and metadata loss; current collision risk is prospective, not a defect in this snapshot.
- **Minimal recommended fix:** Parse and validate the complete source into a temporary model, reject module/function collisions, retain source `name`/`return` metadata, then atomically replace the output only after successful rendering and formatting.

## Standards findings

### STD-1 — High — Documented error-normalization behavior is not implemented

`docs/architecture.md:44` is an explicit repository standard, not merely a design aspiration. S4 demonstrates the breach and its fix.

### STD-2 — Medium — Response classification is duplicated

`lib/meta_ads/client.ex:51-55` and `:86-91` repeat the same status/transport branches. This is a **Duplicated Code** judgment call, and S4/S10 show the concrete divergence already caused by it. Extract one execution/classification path.

### STD-3 — Low — `Model.request/9` carries an unused abstraction parameter

The operation macro passes `__MODULE__` at `lib/meta_ads/model.ex:49-59`, but `request/9` discards it as `_model` at `:101-111`. This is **Speculative Generality**: removing the parameter reduces machinery without losing behavior.

### STD-4 — Low — Generated root-operation names repeat HTTP verbs

`lib/meta_ads/models/integrity_appeal.ex:5,9,15` exposes `get_get_*` and `create_post_*`; `lib/meta_ads/models/ad_campaign_placement.ex:5` exposes `get_get`. The naming algorithm at `lib/mix/tasks/meta_ads.generate.ex:168-191` prepends a method to upstream names that already contain one. This is a **Mysterious Name** judgment call and should be cleaned before v0.1 creates a public compatibility surface.

Axis summary: Spec has 12 findings, with S1-S2 worst at Critical; Standards has 4 findings, with STD-1 worst at High.

## Test adequacy

The existing tests verify useful narrow behavior: versioned object-ID escaping, ordinary query/form encoding through a recording adapter, HMAC proof bytes, missing-key and enum rejection, hostile paging-host rejection, response helpers, and a small core generated surface. They do not exercise the production transport.

| Missing test | Defect already demonstrated? |
| --- | --- |
| Direct default-adapter GET/POST/error/TLS contract | Yes — S1, S2 |
| Each `basePath` URL shape | Yes — S3 |
| 2xx Graph error envelope | Yes — S4 |
| File/multipart operation behavior | Yes — S5 |
| Positive pagination with client defaults | Yes — S10 |
| Required `nil` and empty values | Yes — S8 |
| Custom-adapter content type | Yes — S9 |
| Non-JSON error diagnostics | Yes — S11 |
| Generator malformed input, collisions, and atomicity | No current snapshot collision; prospective risk in S12 |
| Reachable provenance and Hex license/package validation | Yes — S6, S7 |

## Independent proof results

All four required commands passed at the pinned target:

| Command | Result |
| --- | --- |
| `mix compile --warnings-as-errors` | exit 0; no warnings |
| `mix test` | exit 0; 10 tests, 0 failures |
| `mix meta_ads.generate` | exit 0; generated 1,074 models and 1,489 operations; skipped 1 dynamic endpoint |
| `git diff --exit-code` | exit 0; no tracked diff after regeneration |

These results establish build cleanliness, the current tests' result, and generator idempotence. They do not invalidate the focused runtime failures above. `git diff --exit-code` intentionally does not report the untracked work order/review artifacts.

## Release blockers

1. Fix and directly test the default HTTP adapter (S1).
2. Establish HTTPS verification and a no-cross-origin-redirect credential boundary (S2).
3. Correct all six `basePath` paths (S3).
4. Normalize 2xx Graph error envelopes as failures (S4).
5. Remove/reject the 27 unsupported upload operations or implement a real multipart contract (S5).
6. Verify the complete vendored snapshot and repair its upstream provenance (S6).
7. Resolve and accurately publish the package's multi-license metadata/file set (S7).

Non-blocking follow-up after those gates: strengthen required-value validation, complete the custom transport contract, unify pagination execution, retain raw error diagnostics, make generation atomic/collision-safe, and clean generated public names before declaring the related interfaces stable.
