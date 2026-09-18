<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# Risks

What could go wrong in this library, what we watch for it, and what we would
do. Written on 2026-09-09 as part of the source of truth issue #49 asked
for. A PR that creates a risk adds it here; a PR that removes one deletes
the entry rather than marking it closed.

## Technical

### The product is text, and most tests assert on text

Every generator returns a string and most tests are `assert result =~ "..."`.
A test can pass on Kotlin that does not compile, and did — #20, #23, #24,
#30 and #33 were all found by a human reading emitted strings.

*Watch:* the `kotlin-compile-gate` CI job, blocking and green since #52. It
compiles the emitted Kotlin and, since #58, runs it against real `Rpc.Runner`
responses.
*Do:* run both halves locally before pushing any generator change. Their
green is only worth what they cover: they exercise the test domain's
resources, so a shape no test resource has is still unchecked, and the decode
half only checks the responses the fixture carries. A new response shape
needs a new check in `roundtrip/Roundtrip.kt`, or it is unwatched.

### The shared core formats values by type, and this library never asks it to

`Rpc.Runner.execute_action/7` formats a response with
`AshIntrospection.Rpc.Pipeline.format_output/1`, which formats field names and
nothing else. Nothing in `lib/` calls `AshIntrospection.Rpc.ValueFormatter`, so
every value the shared core would format by type reaches the JSON encoder raw.
Measured 2026-09-11: a `:vector` attribute arrives as `%Ash.Vector{}`'s packed
binary and raises `Jason.EncodeError`, which is #71. The same path carries
unions, typed maps and custom types with map storage.

*Watch:* the round-trip gate, but only where the fixture goes — it carries no
vector response, because the server cannot produce one.
*Do:* fix #71 with a round-trip entry per shape. The type-aware entry point
`Pipeline.format_output_with_request/3` is not a drop-in: it builds the
`%{success:, data:}` envelope `Runner.build_success_response/1` already builds,
and its `ValueFormatter.format/5` passes a list of records through untouched,
so a list read would lose the field-name formatting it has today.

### Swift is generated and never compiled

`Swift.Codegen` is 742 lines with two test files and no compiler anywhere in
CI. Whatever the Kotlin gate found in the Kotlin generator is likely true of
the Swift one, unobserved.

*Watch:* nothing watches it today.
*Do:* decide #31 — finish it with a compile gate of its own, or delete it.
Half a generator that nobody compiles is worse than neither.

### The channel client is static

`Rpc.Codegen.PhoenixChannel` takes no resource and no action; the same text
is emitted for every application. It cannot express a per-action payload, a
typed event, or anything the DSL knows (#35).

*Watch:* every channel feature request lands as a change to one hardcoded
string.
*Do:* if channel use grows past `AshRpcChannel.call/5`, drive it from the
same `{resource, action, rpc_action}` tuples the HTTP renderer uses.

### The client owns a wire format it does not share with the server

The channel client hand-writes Phoenix's v2 serializer format in Kotlin —
four binary layouts and a text array. The Elixir side of that format lives
in the `phoenix` package, not here, so a Phoenix change to it would
otherwise be invisible to this repository.

*Watch:* the `the Phoenix v2 wire format the generated client is written
against` block in `phoenix_channel_test.exs`. It asserts each layout against
`Phoenix.Socket.V2.JSONSerializer` itself and names the Phoenix version it
was verified on.
*Do:* on a Phoenix major bump, re-read
`deps/phoenix/lib/phoenix/socket/serializers/v2_json_serializer.ex` and
update both the assertions and the generated Kotlin together. A mismatch
produces frames the server drops in silence, with no error on either side.

### The v2 switch changes the wire for every existing consumer

The socket now sends `vsn=2.0.0` and frames text as a JSON array. Any
consumer on an older generated client keeps talking v1 and is unaffected,
but a regenerated client will not work against a server whose socket
declares only the v1 serializer.

*Watch:* the alpha notice, and the CHANGELOG entry naming this as breaking.
*Do:* nothing for the stock Phoenix socket, which offers both. A host that
narrowed `serializer:` to v1 must add v2.

### `main` is not formatter-clean

`mix format --check-formatted` fails on ten files that predate the current
rules, so the check cannot go into CI (#38) and formatting drift is invisible
in review.

*Watch:* nothing.
*Do:* close #38 as one mechanical commit, then add the check to the `test`
job.

### Codegen trusts the manifest's type list, and the request path ignores it

Both code generators declare one class per embedded resource in the persisted
manifest's `types` (#84). A type missing from that list is a class the
generated file does not declare, and Kotlin that names it does not compile.
Two ways to lose one are known:

- A type reached only through a `first` aggregate. The aggregate's `type` is
  `nil` when the manifest is built, so Ash's reachability walk misses it.
  `Test.PrivateMeta` is the fixture. No data class carries aggregates, so no
  generated file names it today. This was an upstream Ash gap and **ash
  3.33.6 closes it**: measured 2026-09-18, `Test.PrivateMeta` reaches
  `manifest.types` on 3.33.6 with `ash_introspection` 0.5.1, which fails the
  `refute` below and the module list in
  `manifest/embedded_resources_test.exs`. `mix.lock` holds ash at 3.33.5, so
  this repository has not taken that release. `mix.exs` allows it
  (`>= 3.33.4`), so a consumer already on 3.33.6 gets a `PrivateMeta` class
  it did not get before. Taking the release here means flipping both tests
  and deleting this bullet; it needs its own ticket.
- A type reached only through a resource that was not loaded when the manifest
  was built. `BuildManifest` now compiles every domain resource first; that
  race dropped a type in 6 of 6 measured edits before.

Meanwhile `Rpc.Runner.discover_action/2` still scans `Ash.Info.domains/1` per
request, so the request path and the manifest can disagree with nothing
comparing them.

**What we watch.** The Kotlin compile gate, which fails on any undeclared
class. The embedded-class tests in `resource_schemas_test.exs` and
`swift/codegen_test.exs`, one per route. The `refute` on `PrivateMeta` in
`resource_schemas_test.exs` fails the day Ash fixes the aggregate gap.

**What we would do.** When the `PrivateMeta` test fails, delete this bullet
and turn the test into an assertion. If a consumer reports an undeclared
embedded class, find the route, add a fixture for it, and fix reachability
upstream rather than walking attributes here again. The request path moves
onto the manifest in the rest of `ash_introspection#23` stage 4.

### `Code.ensure_compiled!` inside a transformer can deadlock

`BuildManifest` forces every resource of every domain, and every module the
generated manifest names, to compile. Since #84 that is every domain resource,
not only the `kotlin_rpc` ones, so the surface is wider: a resource no client
ever sees can now deadlock the build too. If one of those modules ever gains a
compile-time dependency back on the manifest module, the parallel compiler
deadlocks rather than erroring usefully.

**What we watch.** Nothing automated. The shape that causes it is a resource
or domain file that `use`s or otherwise compile-depends on the consumer's
manifest module.

**What we would do.** Keep the injected edges pointing at domains only, and
say in `AshKotlinMultiplatform.Manifest`'s moduledoc that a resource must never
reference the manifest module. If a consumer reports a hang, `mix compile
--no-compile` plus `mix xref graph --label compile` on their app names the
cycle.

### A scoped manifest stops tracking its config

`use AshKotlinMultiplatform.Manifest, domains: [...]` suppresses the
`Application.compile_env/3` edge, because a module scoped to an explicit list
does not depend on `config :my_app, ash_domains:`. That is correct and it is
also a foot-gun: a consumer who copies the test-only option into a production
manifest gets a module that never notices a domain being added.

**What we watch.** `compile_edges_test.exs` asserts the suppression, so the
behaviour cannot drift silently, and the installer never writes `:domains`.
Nothing stops a consumer writing it by hand.

**What we would do.** The moduledoc carries a warning admonition. If it bites
anyone, make the option raise unless `Mix.env() == :test`.

### `generate/1` scopes by entrypoints, not by domains

`Ash.Info.Manifest.Generator.generate/1` takes `:otp_app` and calls
`Ash.Info.domains/1` itself; there is no `:domains` option. Scoping works only
because the generator ignores its own domain walk when `:action_entrypoints` is
a list. Passing `nil` there — or refactoring
`Entrypoints.action_entrypoints/2` to return `nil` on an empty DSL — silently
widens a scoped manifest to the whole application.

**What we watch.** `decorate_manifest_test.exs` asserts `Test.Todo` is absent
from the scoped manifest, which fails if the scoping ever widens.

**What we would do.** Keep `action_entrypoints` unconditional. An empty list is
the correct answer for a domain list with no `kotlin_rpc` blocks and is not the
same as `nil`.

## Operational

### Two generators, one hex release, alpha API

The README advertises Kotlin, Swift, filters, pagination and validation. Not
all of it works, and the package is on hex where anyone can depend on it.

*Watch:* the alpha notice at the top of the README and in `mix.exs`.
*Do:* keep the notice until #22, #24 and #31 close. Do not cut a release
that quietly widens what is claimed.

### The gate needs a JDK and a Gradle that CI installs each run

The fixture has no committed wrapper, so a local run needs JDK 21 and Gradle
9.7 on the path, and CI resolves the Kotlin and Ktor artifacts from Maven
Central.

*Watch:* the `kotlin-compile-gate` job's setup steps.
*Do:* if Maven Central flakiness starts failing the job, cache the
dependency jars rather than committing a wrapper.

## Product

### The rpc_action surface options read like authorization

`get_by`, `enable_filter?` and `enable_sort?` narrow what an endpoint accepts,
which is what a permission looks like from the outside. They are not one (#25).
Ash policies run on every request regardless of what the DSL exposes, and
`enable_filter? false` hides no rows — it removes the client's ability to ask
for fewer, so the action answers with the whole table.

*Watch:* the "not authorization" paragraph under the DSL example in the README,
and the same words in the `rpc_action` moduledoc in
`lib/ash_kotlin_multiplatform/rpc.ex`.
*Do:* repeat that framing on every option added to this group, and answer an
access question with a policy, never a DSL switch.

### The request half of the client is still untyped

`RpcResult<T>` types the response (#22) and `AshRpcError` types the failure
(#24), but a config's `filter` and `page` are still
`Map<String, JsonElement>?`. `FilterTypes` emits a `{Resource}FilterInput`
per resource that nothing references, so `generate_filter_types: true`
produces dead code.

*Watch:* #65, and whether a consumer hand-builds a filter map and gets it
wrong with no compile error.
*Do:* type `filter` as `{Resource}FilterInput?` and `page` as a page config,
gated on `generate_filter_types?/0` so the flag keeps meaning something.

### Two hand-written serializers read two shapes each

`AshPage<T>` and `AshMetadata<T, M>` decode a JSON shape the request
decides, not the action (#22). `AshMetadata` uses a heuristic: an object
carrying both `data` and `metadata` is the envelope.

*Watch:* a resource that publishes attributes named both `data` and
`metadata`, read with the metadata narrowed away — the only input that
misreads.
*Do:* the round-trip gate decodes both shapes of both types. Keep a check
there for any new shape `Rpc.Runner` learns to send.
