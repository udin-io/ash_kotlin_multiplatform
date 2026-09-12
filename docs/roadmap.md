<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# Roadmap

Where the library has been and where it is going. Reconstructed on
2026-09-09 from `git log` and the open issues, as the source of truth issue
#49 asked for. Move an item here in the same PR that merges it, not
afterwards.

## Shipped

| When | What |
| ---- | ---- |
| 2025-12-20 | First cut: the RPC pipeline, hooks, and the resource and domain DSL extensions |
| 2025-12-21 | Modular codegen architecture mirroring `ash_typescript` (#1) |
| 2025-12-21 | Swift generator and the Phoenix RPC controller (#5); released as 0.1.2 and 0.1.3 |
| 2026-09-07 | `Instant` serialization across kotlinx-datetime versions (#10) |
| 2026-09-07 | Base filter types routed through `TypeMapper` so `datetime_library` reaches them (#14) |
| 2026-09-07 | `Rpc.Runner` honours the `metadataFields` the client sends (#15) |
| 2026-09-07 | Removed the unwired `ValidationSchemas` module and its dead `javax.validation` import (#16) |
| 2026-09-09 | CI: compile, test and dependency audit (#40) |
| 2026-09-09 | Fixed atom exhaustion and 500s in RPC field selection (#18, #19) |
| 2026-09-09 | Dependency floors raised past 34 advisories (#42) |
| 2026-09-09 | The Kotlin compile gate: a Gradle fixture and a CI job (#37, PR #47) |
| 2026-09-09 | Generated Kotlin compiles for map, union and unmapped types (PR #50) |
| 2026-09-09 | The generated Kotlin compiles and the gate enforces it (#44, #45, #46) |
| 2026-09-09 | This source of truth, the v2 channel protocol, and binary channel payloads (#49) |
| 2026-09-09 | The generated Kotlin decodes the server's own responses (#24, PR #56) |
| 2026-09-10 | One shared `Json`, `JsonElement` for untyped shapes, and a decode gate in CI (#51, #54, #58) |
| 2026-09-11 | Typed results: every RPC function returns `RpcResult<T>` (#22) |
| 2026-09-11 | Six `rpc_action` options the shared core already honoured: `get?`, `get_by`, `identities`, `not_found_error?`, `enable_filter?`, `enable_sort?` (#25, PR #66) |
| 2026-09-11 | Kotlin types for vector, money, ltree and ULID, plus the `AshMoney` class a money field needs (#30) |
| 2026-09-11 | Stage 4 formats output values by Ash type, so a vector response encodes; `field_names` honoured on both sides (#71) |
| 2026-09-12 | `AshKotlinMultiplatform.Manifest`: one compile-time `Ash.Info.Manifest`, decorated and persisted (#73) |

## In progress

| Issue | What | State |
| ----- | ---- | ----- |
| #73 | Declare and decorate the manifest here — stage 3 of 5 of `ash_introspection#23` | PR open |

## Next

Ordered by what unblocks the most.

| Issue | What | Why now |
| ----- | ---- | ------- |
| `ash_introspection#23` stage 4 | Delete `AshIntrospection.Codegen.TypeDiscovery`; codegen reads the manifest only | Stage 3 built the manifest; nothing reads it on the request path yet |
| #38 | Make `main` formatter-clean and put the check in CI | One mechanical commit; unblocks review signal |
| #65, #53 | Typed `filter` and `page` in the request config | The response is typed now; the request still takes untyped maps, so `FilterTypes` is dead code |
| #48, #53 | The runner mangles unconstrained map keys on the way IN; FilterTypes emits unpublished resources | #71 fixed the output half: an untyped map's keys now survive as written, but `Runner` parses `input` before it knows a field's type, so a key sent as `createdBy` is still stored as `created_by` |
| #57 | Error keys ignore the output field formatter | The decode gate now reads those keys |
| #17, #43 | Unstable output order across builds | A regenerated file should diff empty |
| #35 | The channel client is static and cannot send most params | Blocks any per-action channel work |
| #31 | Decide the fate of the half-built Swift generator | It is generated and never compiled |

## Decided against

Nothing yet. When something is refused, record it here with the reason, so
the next reader does not re-propose it.
