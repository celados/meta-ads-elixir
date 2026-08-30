---
type: Issue
title: Independent Codex review of meta_ads v0.1.0
description: Adversarial review contract for the initial Elixir Meta Ads SDK implementation.
status: closed
review_target: 206eaf8e41b9d627a78abb8ece44f930f5a07e7c
generated:
  by: codex/gpt-5
  at: 2026-08-30T15:50:00+08:00
---

# Independent Codex review of meta_ads v0.1.0

## Outcome

Review the complete repository at commit `206eaf8e41b9d627a78abb8ece44f930f5a07e7c` as an independent SDK reviewer. The deliverable is a falsifiable review, not implementation.

## Required context

- `README.md`
- `docs/architecture.md`
- `mix.exs`
- `lib/meta_ads.ex`
- Everything under `lib/meta_ads` except the bulk-generated `lib/meta_ads/models`
- Representative generated modules:
  - `lib/meta_ads/models/ad_account.ex`
  - `lib/meta_ads/models/campaign.ex`
  - `lib/meta_ads/models/ad_set.ex`
  - `lib/meta_ads/models/ad.ex`
  - `lib/meta_ads/models/ad_creative.ex`
  - `lib/meta_ads/models/ads_insights.ex`
  - `lib/meta_ads/models/integrity_appeal.ex`
- `lib/mix/tasks/meta_ads.generate.ex`
- `priv/codegen/SOURCE.json`
- All tests under `test/`

## Review questions

1. **SDK interface:** Is the caller-facing interface coherent and maintainable, or does it leak Graph API machinery that the runtime should hide?
2. **Correctness:** Are URL construction, query/form encoding, authentication, app secret proof, enum validation, error handling, and pagination semantically correct for Meta Graph API?
3. **Generated surface:** Does the generator preserve schema semantics safely? Look for naming collisions, unsafe path construction, lost metadata, stale-output risks, and idempotence failures.
4. **Runtime design:** Are `Client`, `Model`, `Params`, `Response`, `Error`, and `HTTP` placed at the right seams? Identify shallow modules or accidental coupling.
5. **Security:** Find credential leakage, unsafe redirect/pagination handling, injection, transport pitfalls, and failure modes that erase diagnostic information.
6. **Test adequacy:** Which production-relevant failure modes are untested? Distinguish missing tests from actual defects.
7. **Release readiness:** Identify blocking issues for a public `v0.1.0` Hex/Git release and non-blocking future work.

## Proof contract

Run independently:

```sh
mix compile --warnings-as-errors
mix test
mix meta_ads.generate
git diff --exit-code
```

The reviewer may add focused read-only commands, but must not edit code to prove a hypothesis.

## Constraints

- Review commit `206eaf8e41b9d627a78abb8ece44f930f5a07e7c`.
- Do not modify implementation, tests, dependencies, Git history, or remote state.
- Write only the requested review artifact.
- Do not treat existing documentation claims as evidence; verify against source and commands.
- Findings must be falsifiable and include exact file/line or command evidence.

## Required artifact

Write the complete review to:

`docs/reviews/2026-08-30-codex-review.md`

Use OKF frontmatter with `type: Review`, point `resource` at `./2026-08-30-codex-review.workorder.md`, and include:

- verdict: `approve` or `request-changes`
- summary
- findings ordered by severity
- each finding's evidence, impact, confidence, and minimal recommended fix
- independent proof-command results
- release blockers, if any

The final CLI message must be only a short receipt listing artifact path, proof result, and blockers.
