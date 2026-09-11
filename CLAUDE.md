<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# CLAUDE.md

What is true of THIS repository and would otherwise be rediscovered the hard
way. The global rules apply on top of this file and are not repeated here.
Created 2026-09-09 on first contact, as issue #49 asked.

## Project source of truth

`docs/` is this project's source of truth: [`docs/PROJECT.md`](docs/PROJECT.md)
is the hub, with [`architecture.md`](docs/architecture.md),
[`decisions.md`](docs/decisions.md), [`risks.md`](docs/risks.md) and
[`roadmap.md`](docs/roadmap.md) under it. If any of them is missing, create
it before doing anything else, drawing the diagrams from the code that
exists rather than from the README's claims.

Every PR that changes behaviour, structure, a risk or a decision updates
them **in the same PR**: move the roadmap item, redraw any diagram the
change touched, add or retire the risks it created or removed, record the
decision it made. A merge is not finished until those pages describe `main`
as it now is. A source of truth that lags is worse than none, because
readers trust it.

## The product is Kotlin source, so compile it AND run it

Assertions like `assert result =~ "class Push("` pass on Kotlin that does
not compile. Five defects proved it (#20, #23, #24, #30, #33). Compiling is
not enough either: #24, #51 and #54 all compiled and then threw or read
`null` at decode time. Any change to a generator must go through both halves
of the gate:

```sh
MIX_ENV=test mix ash_kotlin_multiplatform.gen_kotlin_fixture
MIX_ENV=test mix ash_kotlin_multiplatform.gen_roundtrip_fixture
cd test/fixtures/kotlin_compile
gradle compileKotlin --console=plain
gradle run --console=plain
```

`MIX_ENV=test` is load-bearing — it is what puts the test domain into
`:ash_domains` (`config/config.exs`), so it is what gives the generator any
resources to emit at all. The gate needs JDK 21 and Gradle 9.7; there is no
committed wrapper.

`gradle run` decodes real `Rpc.Runner` responses with the generated classes.
Its harness is `test/fixtures/kotlin_compile/roundtrip/Roundtrip.kt`,
hand-written and committed, compiled into BOTH `:datetime_library`
subprojects from that one source — so every check has to compile under
`java.time` and `kotlinx-datetime` alike. Assert on `toString()`, never on a
concrete date class.

## Project-specific lessons

### The gate is blocking and green — keep it that way

Since #52 the `kotlin-compile-gate` job has no `continue-on-error`, and both
`gradle compileKotlin` and `gradle run` exit 0 on `main` with no warnings.
Any warning or error is yours. Run both before pushing a generator change;
the CI job will not merge without them.

### `mix format --check-formatted` fails on `main`

Ten files predate the current formatter rules (#38), so a red check does not
mean you broke something. Run `mix format` on the files you touched and check
the failing list is unchanged, not empty.

### The channel client is hand-written Phoenix protocol, not kotlinx

`Rpc.Codegen.PhoenixChannel` emits its own serializer for Phoenix's wire
format. That format lives in the `phoenix` package, not here, so nothing in
this repository's test suite notices when Phoenix changes it. Read
`deps/phoenix/lib/phoenix/socket/serializers/v2_json_serializer.ex` and
`deps/phoenix/assets/js/phoenix/serializer.js` before touching it — never
work from memory of the format.

Two traps that produce frames the server drops in silence, with no error on
either side:

* The **`vsn` query parameter selects the serializer**, and an absent `vsn`
  means v1, not v2 (`deps/phoenix/lib/phoenix/socket.ex:499`). v1 has no
  binary branch and uses a JSON *object* for text frames; v2 uses a JSON
  *array*. Changing one without the other breaks every frame.
* The **binary push layout is not symmetric**. A client-to-server push has
  five header bytes and carries a ref; a server-to-client push has four and
  carries none. Reusing one layout for both misreads every incoming frame.
  The table in [`docs/architecture.md`](docs/architecture.md) has all four
  layouts.

### `Rpc.Codegen.PhoenixChannel` is static

It takes no resource and no action, so the same Kotlin is emitted for every
application (#35). Do not reach for the `{resource, action, rpc_action}`
tuples inside it; they are not passed in.

### There is one `Json` in the generated file, and it is `ashRpcJson`

Never emit `Json { ... }` or the bare `Json.` companion (which is
`Json.Default`) in generated Kotlin. Both skip the `SerializersModule`, and a
`@Contextual` field decoded or encoded through either throws at runtime while
compiling clean — that was #54, in four separate places.
`AshKotlinMultiplatform.Codegen.SharedJsonTest` counts them, so a new one
fails a test rather than a user's app. If a path genuinely needs different
settings, copy: `Json(from = ashRpcJson) { ... }`.

### An untyped shape is `JsonElement`, never `Any`

kotlinx-serialization has no serializer for `Any` and never will. A bare
`Any` inside a `@Serializable` class does not compile, and `@Contextual Any`
compiles and then throws the moment the field holds something (#50 bought the
first, #51 measured the second). Untyped maps, keywords, tuples, unions
without an owning attribute and unrecognised Ash types all take
`JsonElement`. See `docs/decisions.md` for why an `Any` serializer was
measured and refused.

### A return type names what the REQUEST produces, not what the action suggests

Three of the shapes `Rpc.Runner` sends are decided by the request rather than
by the action, so a generated signature that names one of them is wrong half
the time:

* A read sends a bare JSON array when the request carried no `page` and a
  page object when it did. Ash 3 defaults **every** read to
  `offset? true, keyset? true`, so this is nearly every read.
* A mutation that exposes metadata sends `%{data:, metadata:}` — but only
  while some metadata survives the client's `metadataFields` narrowing, and
  the bare record otherwise.
* A destroy sends the destroyed record, not a boolean:
  `AshIntrospection.Rpc.Pipeline.execute_destroy_action/3` passes
  `return_records?: true`.

`AshPage<T>` and `AshMetadata<T, M>` each carry a hand-written `KSerializer`
that reads both of their shapes (#22). Before adding a branch to
`FunctionCore.determine_return_type/1`, run the action through `Runner` and
look at what comes back — `mix run` against the test domain takes a minute
and the guess takes a release.

### Section generators share no state

Each returns a string and none can see what another emitted, so "was this
type ever generated?" and "did two sections pick the same identifier?" have
nowhere to live. That is the shape (see `docs/decisions.md`), and it is where
#33 and #44 came from. A cross-section check needs the fact threaded in from
`Rpc.Codegen`, not looked up inside a generator: #52 fixed #44 by passing
`ResourceSchemas.generate_data_class/2` the set of resources the same pass
emits a class for. Follow that pattern.

### The runner formats field names, not values

`Rpc.Runner.execute_action/7` calls
`AshIntrospection.Rpc.Pipeline.format_output/1`, which renames keys and stops
there. Nothing in `lib/` calls `AshIntrospection.Rpc.ValueFormatter`, so the
shared core's type-aware formatting — the clause that turns `%Ash.Vector{}`
into a list of numbers, and everything beside it — never runs. A value whose
in-memory form is not JSON-encodable therefore reaches the encoder raw and
raises: measured 2026-09-11, a `:vector` attribute raises
`Jason.EncodeError` on the packed binary (#71).

So a new type needs both halves checked. A Kotlin type that reads the wire
format proves nothing about whether this library can produce that wire
format; run the action through `Runner` and encode the result before
believing it.
