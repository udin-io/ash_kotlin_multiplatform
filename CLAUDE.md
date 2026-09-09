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

## The product is Kotlin source, so compile it

Assertions like `assert result =~ "class Push("` pass on Kotlin that does
not compile. Five defects proved it (#20, #23, #24, #30, #33). Any change to
a generator must go through the compile gate:

```sh
MIX_ENV=test mix ash_kotlin_multiplatform.gen_kotlin_fixture
cd test/fixtures/kotlin_compile && gradle compileKotlin --console=plain
```

`MIX_ENV=test` is load-bearing — it is what puts the test domain into
`:ash_domains` (`config/config.exs`), so it is what gives the generator any
resources to emit at all. The gate needs JDK 21 and Gradle 9.7; there is no
committed wrapper.

## Project-specific lessons

### The compile gate is blocking and green — keep it that way

Since #52 the `kotlin-compile-gate` job has no `continue-on-error`, and
`gradle compileKotlin` exits 0 on `main`. Two warnings are expected, one per
subproject: "Redundant creation of Json format", from `RpcResult.dataAs()`.
Any error is yours. Run the gate before pushing a generator change; the CI
job will not merge without it.

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

### Section generators share no state

Each returns a string and none can see what another emitted, so "was this
type ever generated?" and "did two sections pick the same identifier?" have
nowhere to live. That is the shape (see `docs/decisions.md`), and it is where
#33 and #44 came from. A cross-section check needs the fact threaded in from
`Rpc.Codegen`, not looked up inside a generator: #52 fixed #44 by passing
`ResourceSchemas.generate_data_class/2` the set of resources the same pass
emits a class for. Follow that pattern.
