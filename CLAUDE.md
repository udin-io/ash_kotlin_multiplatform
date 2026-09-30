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

### Gradle and Java are not on the global mise path

`kotlin-compile-gate` steps (`gradle compileKotlin`, `gradle run` in
`test/fixtures/kotlin_compile`) fail with "command not found" under a bare
`mise exec --` because gradle and java aren't installed there globally.
Prefix every such command with
`mise exec gradle@9.7.0 java@temurin-21 --` (#38).

### `.formatter.exs` needs `locals_without_parens` for this library's DSL

Without it, `mix format` rewrites `rpc_action :list_todos, :read` into
`rpc_action(:list_todos, :read)` in test resources and README examples,
making DSL calls read like function calls. Regenerate the list with
`mix spark.formatter --extensions AshKotlinMultiplatform.Rpc,AshKotlinMultiplatform.Resource,AshKotlinMultiplatform.Manifest.Dsl`
after adding or changing a DSL entity or option — never hand-edit the
`spark_locals_without_parens` list (#38).

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

A generic action is the opposite case: its return type names what the action
returns, not the resource that owns it. `Book.summarize` returns `Summary`,
so `summarizeBook` returns `RpcResult<Summary>`, never `RpcResult<Book>`
(#87). `Resource.Info.returned_resource/1` names that resource for codegen
and for `Rpc.Runner`'s no-`fields` default alike (#88), and codegen names
only a class in `emitted`, the `Manifest.published_resources/1` list
`Rpc.Codegen` threads into `FunctionCore`. Do not route it back through ash_introspection's
`action_returns_field_selectable_type?/1`: that answers
`:not_field_selectable_type` for every embedded return.

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

`Rpc.Codegen.declaration_fragments/2` is that pattern applied to "did two
sections pick the same identifier?" (#33): it calls the same per-item
generator function every section's real output already calls, tags each
fragment with a human-readable source, and hands the full list to
`Codegen.Declarations.check/1` before anything joins. Adding a new
per-item generator function (a new typed-query shape, a new filter kind)
means adding it to `declaration_fragments/2` too, or its output is
invisible to the check. `ResourceSchemas.generate_all_schemas_fragments/2`
is the one place this threading also changes behaviour, not just
structure: it keeps every enum and union `collect_types/1` finds,
including a same-named duplicate, where `generate_all_schemas/2` used to
silently drop one via `Enum.uniq_by/2`.

The one exception is the list of resource classes itself:
`Manifest.published_resources/1` is read from the compiled manifest, so
`TypeMapper` asks it directly rather than having it threaded through six
generators. `Rpc.Codegen` builds `emitted` from the same call, so a field and
a signature cannot disagree (#91). A `:struct` whose `instance_of` is not in
that list is `JsonElement`.

### A new type needs the server half checked too

`Rpc.Runner.execute_action/7` formats a response with
`Rpc.Pipeline.format_data/2`, which formats values by Ash type: a `:vector`
becomes a list of numbers (#71, since `b90fe55`). Before that the runner
renamed keys only, and a vector reached the encoder as a packed binary and
raised `Jason.EncodeError`.

A new type still needs both halves checked. A Kotlin type that reads the wire
format proves nothing about whether this library can produce that wire
format; run the action through `Runner` and encode the result before
believing it.

### Embedded classes come from the manifest; a missing one is a manifest bug

Since #84 both generators declare exactly the embedded resources in
`Manifest.embedded_resources/1`, and code generation raises without
`config :ash_kotlin_multiplatform, :manifest` (the test env names
`AshKotlinMultiplatform.Test.Manifest`). When generated Kotlin names an
embedded class it never declares, look at `manifest.types`, not at
`ResourceSchemas`; never add an attribute walk back.

A manifest that drops a type after a file edit is a compile-order race, and
it does NOT reproduce inside ExUnit. Reproduce it outside: add an attribute
to the embedded fixture, run `MIX_ENV=test mix compile`, then read the type's
fields off `Manifest.manifest(Test.Manifest).types` with `mix run`. That is
how the `BuildManifest` pre-compile race was measured, 6 of 6 edits dropped
before the fix and 6 of 6 kept after.

### A test that writes application env must be `async: false`

`Application.put_env/3` is VM-global with no per-process scope, so a
`setup`/`on_exit` pair does not contain it: every other test running at that
instant reads the new value. The keys that matter here are `:manifest`,
`:ash_domains`, `:datetime_library`, `:output_field_formatter` and
`:untyped_map_type` — `Rpc.Pipeline.request_config/0` and the generators read
them on every call.

Igniter counts as writing env. `Igniter.compose_task/3` and `apply_igniter!/1`
apply the test project's `config/config.exs` with `Application.put_all_env/1`
for the length of the task (`deps/igniter/lib/igniter.ex:1697`). That is what
made `install_test.exs` flake at 3 runs in 25 under `--max-cases 8`: a
concurrent `Rpc.Runner` test read `:manifest` as the test project's module and
`persisted(:manifest)` raised "is not a Spark DSL module" (#108). It looks
green locally and goes red on a loaded runner.

Before adding a write, check the function under test actually reads the key.
Two cases in `serial_name_test.exs` set `:output_field_formatter` around
`generate_enum_class/1`, which never reads it.

### An upgrade task's module name comes from the hex app name, not a guess

`mix igniter.upgrade ash_kotlin_multiplatform` resolves the package's
upgrade task with `Mix.Task.get("ash_kotlin_multiplatform.upgrade")`
(`deps/igniter/lib/igniter/upgrades.ex`), which only ever resolves
`Mix.Tasks.AshKotlinMultiplatform.Upgrade` — Mix's ordinary Task-name
convention on the hex app name, `:ash_kotlin_multiplatform`. Any other
module name compiles fine and Igniter still reports the package as missing
an upgrade task, with no other error to point at the mismatch.

Notices go through `Mix.shell().info/1` directly, never
`Igniter.add_notice/2`: ash_introspection #99 measured that
`Igniter.CopiedTasks.upgrade/1`, the path the usual `igniter_new` archive
runs, never calls `Igniter.do_or_dry_run/2`, so a notice added the ordinary
way is silently discarded there. Test it with `Mix.shell(Mix.Shell.Process)`
and `assert_received {:mix_shell, :info, [text]}` around
`Igniter.compose_task/3`, not `Igniter.Test.assert_has_notice/2`, which
only sees the queue this bug drops from.

### `mix ash.codegen` finds an extension's `codegen/1` by scanning, not config

`Ash.Mix.Tasks.Helpers.extensions!/2` walks every app in the dep tree that
depends on `:ash` or `:spark`, calls `Ash.Info.defined_extensions/1` on
each, and `Mix.Tasks.Ash.Codegen.run/1` then gates on
`function_exported?(extension, :codegen, 1)`. An extension with no
`codegen/1` is silently skipped — `mix ash.codegen --check` reports success
having checked nothing for it, which is what made #17/#43's fix invisible
to `--check` until #26 added `AshKotlinMultiplatform.Rpc.codegen/1`.

That task also always appends `--name <value-or-nil>` to the argv it
forwards, unless `--name` is already present. `--name` is not in this
task's `OptionParser.parse/2` `strict:` list, and that is fine:
`OptionParser.parse/2` never raises on an unrecognized switch regardless of
`strict:` — only `parse!/2` does — so the extra switch (and a literal `nil`
value, not the string `"nil"`) lands in the ignored third tuple element.
Verified directly with `OptionParser.parse(["--check", "--name", nil],
strict: [check: :boolean])` at the console: `{[check: true], [nil],
[{"--name", nil}]}`, no raise.

### `put_unique/4` needs a manifest module, not just two domains

Two domains each declaring `rpc_action :create_thing` compile
individually with no error. `put_unique/4` runs inside `DecorateManifest`,
a transformer on the *manifest* module
(`Manifest.Transformers.BuildManifest` → `DecorateManifest`), not on
`Ash.Domain` compilation. The raise only fires once something builds a
manifest that reads both domains — `use AshKotlinMultiplatform.Manifest,
domains: [...]` in a test, or the app's own manifest module (built from
`Application.compile_env(:ash_domains)`) in production. Every real
consuming app has exactly one manifest module — the library raises
without `config :ash_kotlin_multiplatform, :manifest` — so this is a
mechanism note, not a gap: the guard fires in practice. A test that wants
to exercise `put_unique/4` for two domains needs a manifest module built
over both, not just the two domains compiled (#33).
