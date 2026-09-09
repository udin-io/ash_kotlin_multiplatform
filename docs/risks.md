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

*Watch:* the `kotlin-compile-gate` CI job, blocking and green since #52.
*Do:* run it locally before pushing any generator change. Its green is only
worth what it covers: it compiles the test domain's resources, so a shape no
test resource has is still unchecked.

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

## Operational

### Two generators, one hex release, alpha API

The README advertises Kotlin, Swift, filters, pagination and validation. Not
all of it works, and the package is on hex where anyone can depend on it.

*Watch:* the alpha notice at the top of the README and in `mix.exs`.
*Do:* keep the notice until #22, #24 and #31 close. Do not cut a release
that quietly widens what is claimed.

### The compile gate needs a JDK and a Gradle that CI installs each run

The fixture has no committed wrapper, so a local run needs JDK 21 and Gradle
9.7 on the path, and CI resolves the Kotlin and Ktor artifacts from Maven
Central.

*Watch:* the `kotlin-compile-gate` job's setup steps.
*Do:* if Maven Central flakiness starts failing the job, cache the
dependency jars rather than committing a wrapper.

## Product

### The generated client returns an untyped result

`RpcResult` is untyped and the generated per-action result types are
orphaned (#22), so the end-to-end type safety the README leads with stops at
the response boundary.

*Watch:* #22, and #24 alongside it — the client cannot decode the server's
own error shape either.
*Do:* fix them together. Typed success with untyped failure is not type
safety.
