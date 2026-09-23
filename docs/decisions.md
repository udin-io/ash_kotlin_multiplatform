<!--
SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors

SPDX-License-Identifier: MIT
-->

# Decisions

The choices that still shape this code, one dated entry each: what was
decided, why, and what it cost. Reconstructed on 2026-09-09 from the commit
history and the code, as the source of truth issue #49 asked for. This file
replaces an ADR directory; git is already the journal, so a decision that no
longer shapes anything gets deleted rather than marked superseded. Add an
entry in the same PR as the change that makes the decision.

## 2025-12-20 — Mirror ash_typescript's modular codegen shape

Section generators, one module each, each returning a string, concatenated
in a fixed order by `Rpc.Codegen`. Chosen because `ash_typescript` had
already proven the shape and the port could follow it module for module.

Cost: the generators share no state, so anything that spans sections —
knowing that a referenced type was never emitted, or that two sections
picked the same Kotlin identifier — has no place to live. #33 and #44 both
came from that gap. The fix each time is to thread the fact in from
`Rpc.Codegen` rather than look it up in a generator.

## 2025-12-21 — Ship a Swift generator alongside the Kotlin one

`Swift.Codegen` and `Swift.TypeMapper` were added in the same release as the
Phoenix controller.

Cost: it is half a generator. It has two test files against the Kotlin
side's dozen, it is not in the compile gate, and no CI job compiles Swift at
all. Issue #31 is open on whether to finish it or delete it.

## 2026-09-09 — Depend on AshIntrospection for the shared RPC core

`Rpc.Pipeline` is a thin Kotlin-flavoured wrapper over
`AshIntrospection.Rpc.Pipeline`; `Rpc.Runner` and the field formatters go
through the same package.

Why: field selection, error shaping and formatter rules are identical across
the TypeScript, Kotlin and Swift clients, and three copies would drift.

Cost: a bug in the shared core lands here as a bug in this library with no
local fix. Issue #48 is one — the runner reaches for the type-blind
`format_output/2`.

## 2026-09-09 — Raise dependency floors to the newest patched release

`mix.exs` pins `ash ~> 3.33`, `ash_phoenix >= 2.3.25`, `phoenix >= 1.8.9`,
`plug >= 1.19.5`, each annotated with the CVEs it clears.

Why: a library's floor is what every consumer inherits, so a low floor
silently permits a vulnerable transitive version in an app that never
audited it.

Cost: consumers on older Ash cannot upgrade this library without upgrading
Ash first. Accepted while the package is alpha.

## 2026-09-09 — Compile the generated Kotlin in CI, and block on it

`test/fixtures/kotlin_compile` is a Gradle project with one subproject per
`datetime_library` setting; the `kotlin-compile-gate` job runs
`gradle compileKotlin`. It shipped with `continue-on-error: true` because the
generated Kotlin did not compile, and lost it in #52 once the sixteen errors
it found (#44, #45) were fixed.

Why: this library's entire product is Kotlin source and nothing had ever
compiled it. Five "does not compile" defects had all been found by a human
reading emitted strings.

Cost: CI now needs a JDK and a Gradle, and the gate only compiles what the
test domain's resources produce. A generated shape no test resource has is
still unchecked.

## 2026-09-09 — An unpublished relationship is dropped, not generated

`Author` has a public `has_many :secrets` to a resource the Kotlin DSL never
publishes. `ResourceSchemas.generate_data_class/2` now omits the field
rather than emitting `List<Secret>` against a class that exists nowhere.

Why: the server already refuses it. `Rpc.Runner`'s field selector gates on
`Resource.Info.kotlin_multiplatform_resource?/1`, so a nested request into
`Author.secrets` comes back `unknown_field`. A field no round trip can
deliver is worth nothing to a client. Generating the missing type would
contradict the DSL, and a verifier error would turn any public Ash
relationship into a build break.

Cost: the omission is silent. A developer who expects the field has to know
the destination must carry the `kotlin_multiplatform` extension.

## 2026-09-09 — The channel client owns Phoenix's v2 format by hand

`PhoenixMessage` lost `@Serializable`; the generated `PhoenixSerializer`
encodes text frames as the JSON array v2 expects and the socket sends
`vsn=2.0.0`.

Why: a `@Serializable` data class can only emit a JSON object, which is the
v1 shape, and v1's serializer has no binary frame at all. Binary payloads
(#49) are impossible without v2, and v2's text frame is an array.

Cost: the client now hand-writes a format that lives in the `phoenix`
package, so a Phoenix change to it is invisible here. The mitigation is a
test block asserting the format against `Phoenix.Socket.V2.JSONSerializer`
itself, and it is the reason that risk is written down.

## 2026-09-09 — A separate `pushBinary`, not a widened payload type

`channel.push(event, jsonElement)` is unchanged; `channel.pushBinary(event,
byteArray)` is new. `Push.payload` became a `ChannelPayload` so it stops
claiming a binary push carried JSON, but its `JsonElement` constructor and
its `await()`/`receive()` signatures are kept.

Why: the JSON path is every existing user of this library. Widening
`push`'s parameter to a sealed type would have made the common call read
`push(event, ChannelPayload.Json(x))` — a worse API for everyone, to serve
the rarer case.

Cost: two lanes to keep in step. `await()` returns null for a reply the
server sent as binary, and `awaitBinary()` returns null for a JSON one;
`awaitPayload()` is the one that never hides a reply.

## 2026-09-10 — `JsonElement` for every untyped shape, not an `Any` serializer

Untyped maps, keywords, tuples, unions and unmapped Ash types now reach
Kotlin as `JsonElement` (`Map<String, JsonElement>`, `List<JsonElement>`).
This replaces the 2026-09-09 decision to annotate them `@Contextual Any`,
which bought the compile and nothing else: #51 measured a populated untyped
map still throwing `SerializationException: Serializer for class 'Any' is
not found`.

The alternative was registering a hand-written `Any` serializer on the
module. It was prototyped and measured against the real response on
2026-09-10 rather than argued about, and it loses data: a JSON integer past
`Long.MAX_VALUE` decodes to a `Double` and re-encodes as
`1.2345678901234567E19`, a different number. Every integer lands as `Long`,
so the obvious `as Int` throws. Encoding is a closed `when` over
String/Number/Boolean/Map/List that throws on anything else, with no
compile-time signal. And it works only while the value travels through the
one configured `Json` — the type says `Any?`, and nothing in the type warns
that `Json.decodeFromString<Todo>(text)` will throw.

`JsonElement` has none of that. It needs no `SerializersModule`, so it
decodes through any `Json` a consumer builds; `JsonPrimitive` keeps the
literal a number arrived as; and the type states the truth, which is that the
shape is unknown.

Cost: breaking for anyone reading these fields today —
`metadata["retries"] as Int` becomes
`metadata["retries"]?.jsonPrimitive?.int` — and every call site is more
verbose than an `Any` that happened to work. `:untyped_map_type` and
`:type_mapping_overrides` still accept a value naming `Any`, and
`annotate_contextual_types/1` still annotates it, so a consumer who wants
the old shape keeps compiling and takes the decoding on themselves.

## 2026-09-10 — One `Json` in the generated file, and it is public

`val ashRpcJson` carries the `SerializersModule`, and every generated encode
and decode path uses it: `createHttpClient()`, `RpcResult.dataAs()`, the
Phoenix channel client, and all 46 request-payload encodes.

Why: four paths each built their own, and only `createHttpClient()`
registered the module (#54). Public rather than private because `dataAs()` is
`inline` and an inline body can only reach public declarations — and because
a consumer decoding by hand should be able to reach the same configuration
rather than rebuild it wrong.

Cost: the channel client's `encodeDefaults = true` is gone. That is
deliberate, because carrying it to the HTTP payloads would send every unset
input field as an explicit `null`, which Ash reads as "set this attribute to
nil"; the channel encodes no `@Serializable` class, so it loses nothing. If a
future path does need different settings it must copy `ashRpcJson` with
`Json(from = ashRpcJson) { ... }`, never build a fresh one.

## 2026-09-10 — The CI gate runs the generated Kotlin, not only compiles it

`gradle run` decodes real `Rpc.Runner` responses with the generated classes,
after `gradle compileKotlin` compiles them (#58).

Why: `kotlinc` has no opinion about whether a `@SerialName` matches the key
the server sends. Six filed defects were compile failures and the compile
gate catches all six; three (#24, #51, #54) compiled and then threw or
silently read `null`, and nothing caught those.

Cost: a fixture that has to stay in step. The mix task writes responses and
`roundtrip/Roundtrip.kt` reads them, and a response added without a matching
check proves nothing. The harness is one source compiled into both
`:datetime_library` subprojects, so every check has to assert on `toString()`
rather than on a concrete date class.

## 2026-09-11 — `RpcResult<T>`, not a result class per action

Every generated RPC function returns `RpcResult<T>` with `T` named for that
action: `RpcResult<Author>`, `RpcResult<AshPage<Author>>`,
`RpcResult<AshMetadata<Event, RegisterEventMetadata>>` (#22).

Why not the `{Action}Result` sealed classes the generator already emitted?
Because nothing could write a helper over them. Fifteen unrelated classes
with the same three properties cannot be the parameter of a
`fun <T> handle(result: RpcResult<T>)`, and every consumer would write the
same `when` fifteen times. They were also wrong on the wire: a
`@Serializable sealed class` makes kotlinx look for a class discriminator,
and `Rpc.Runner` sends none — the defect that made every `validateX()` call
throw in #24. The Swift generator has emitted `RpcResult<T: Codable>` since
it was written, so this is also the two generators agreeing.

Cost: breaking for every caller. `result.dataAs<Todo>()` becomes
`result.data`, and a caller who held an `RpcResult` now holds an
`RpcResult<Todo>`. `dataAs()` survives as an extension on
`RpcResult<JsonElement>`, which is what the channel client returns.

## 2026-09-11 — One page and one envelope type, with hand-written serializers

`AshPage<T>` is what every paginated read returns and `AshMetadata<T, M>` is
what a mutation with exposed metadata returns. Both carry a hand-written
`KSerializer` that reads two different JSON shapes into one type.

Why: which shape the server sends is decided by the request, not by the
action, so a generated function cannot name one. A read answers with a bare
JSON array when the request carried no `page` and a page object when it did
(`AshIntrospection.Rpc.ResultProcessor.process/4`), and Ash 3 defaults every
read to offset **and** keyset pagination, so that is nearly every read. A
mutation wraps its record as `%{data:, metadata:}` only while some metadata
survives the client's `metadataFields` narrowing, and returns the bare record
otherwise (`AshIntrospection.Rpc.Pipeline.add_mutation_metadata/3`). The
alternative — declare one shape and let the other throw — is the defect
class of #24, #51 and #54.

Cost: two serializers this repository maintains by hand, and one heuristic.
`AshMetadata` treats an object carrying both `data` and `metadata` as the
envelope, which misreads a resource that publishes attributes with both of
those names when the metadata has been narrowed away. Nothing else produces
that pair. Both are decoded from real `Runner` responses by the round-trip
gate, including the narrowed-away case.

## 2026-09-11 — The DSL's `get?` reaches the core as the Ash action's `get?`

`Rpc.Runner.execute_action/7` copies the `rpc_action`'s `get?` onto the
introspected `Ash.Resource.Actions.Read` struct before the pipeline sees it
(#25). `get_by` implies `get?`, so naming the lookup fields is the whole
statement and no config can ask for a key and a list in the same breath.

Why: `AshIntrospection.Rpc.Pipeline.execute_read_action/3` reads `action.get?`
for one thing only — choosing `Ash.read_one/1` over `Ash.read/1` — and
builds the query from `action.name`. Setting that one field selects the
single-record path and changes nothing else. The alternative was a new config
key in the shared core, which is a release of `ash_introspection` before this
library could ship the option at all.

Cost: the runner writes to a struct Ash owns. If the core ever reads `get?`
for something besides that branch, the override does more than this library
intends, with no signal. `mix.exs` pins `ash_introspection ~> 0.3`, so that is
the line to re-read on a bump.

## 2026-09-11 — A switched-off read parameter is refused, not dropped

`enable_filter? false` and `enable_sort? false` remove the property from the
generated config class *and* make `Rpc.Runner.check_read_surface/3` reject a
request that sends it anyway (#25).

Why: no current client can send the parameter, so only a stale one reaches
this error — and dropping it in silence would hand that client the whole
table with no way to know it had asked for a subset. The shared core already
reasoned this way about `identity` on a read.

These options shape an action's API surface. They are not authorization. Ash
policies run on every request regardless of what the DSL exposes, and
`enable_filter? false` hides no rows — it removes the client's ability to ask
for fewer. The README and the `rpc_action` moduledoc both say so, because
someone will otherwise reach for it as a security control.

Cost: one error type per switched-off parameter, `filter_not_supported` and
`sort_not_supported`, that every client has to be able to read. Both are
decoded by the round-trip gate.

## 2026-09-11 — `getBy` is a generated lookup class, not a map

A `get_by` read gets its own `@Serializable` data class — `FetchAuthorGetBy`
for the test domain's `rpc_action :fetch_author` — rather than the
`Map<String, JsonElement>` the config's `filter` still uses.

Why: the server requires exactly the configured fields and refuses anything
else, so a client assembling that map by hand would learn at runtime what the
compiler could have told it. A missing field widens the lookup into a
`MultipleResults` naming nothing the caller can act on; an extra one reaches
`Ash.Query.do_filter/2`, which reads a map operand as an operator expression
and turns an exact lookup into an arbitrary predicate.

Cost: one more generated class per `get_by` action, and a wire key two
generators have to spell the same way. `@SerialName` carries the resource's
own field name to match `InputTypes.generate_input_type/2`, and the round-trip
check `#25 getBy encodes the key the server reads` re-encodes the class and
compares it to the payload the fixture's hit was produced by.

## 2026-09-11 — A shared `AshMoney` class, and no union for an ltree

Four types left the unknown-type fallback in #30. Three map to a built-in:
`Ash.Type.Vector` to `List<Double>`, `AshPostgres.Ltree` to `List<String>`,
`AshDoubleEntry.ULID` to `String`. `AshMoney.Types.Money` maps to `AshMoney`,
a `@Serializable data class` `KotlinStatic.generate_money_type/0` emits into
every generated file.

Why a class and not an alias: money is two values. `amount` is a decimal
string and `currency` a code, which is what ash_money's `Jason.Encoder` sends
and what `AshMoney.Types.Money.json_schema/1` documents. `amount` stays a
`String` for the reason `Ash.Type.Decimal` does — reading a currency amount
into a `Double` would round it.

Why `AshMoney` and not upstream's `Money`: the generated file already prefixes
its own shared classes `Ash` — `AshRpcError`, `AshPage`, `AshMetadata` —
and a consumer's own `Money` class is likelier than a clash on that prefix.

Why `List<String>` for an ltree under both `escape?` settings: upstream types
the unescaped case `string | string[]`, because `AshPostgres.Ltree.cast_input/2`
also accepts a dotted string. Kotlin has no untagged union, and the value is a
list of segments in memory either way, so the output type is the same under
both and a generated client always sends segments.

Cost: `AshMoney` is emitted whether or not a consumer uses money, because the
generator cannot see ash_money without depending on it. A Money field cannot
be checked end to end here for the same reason — the round-trip gate has no
money response to decode, so `client_server_contract_test.exs` holds the class
to ash_money's documented shape instead.

## 2026-09-11 — Stage 4 formats by type, and this library keeps its envelope

`Rpc.Runner` called `Pipeline.format_output/1`, which renames field names and
never looks at a value, so `AshIntrospection.Rpc.ValueFormatter` never ran on
a response. A `:vector` attribute therefore reached `Jason` as the packed
binary `%Ash.Vector{}` carries and raised `Jason.EncodeError`, and every
request touching it returned a 500 (#71).

The shared core's type-aware entry point, `format_output_with_request/3`, is
not a drop-in and was not adopted. It builds its own `%{success:, data:}`
envelope, duplicating `Runner.build_success_response/1`, and it hoists action
metadata to a sibling of `data` where this library nests it. Measured on
`ash_introspection` 0.4.1: routing stage 4 straight through it fails seven
tests, all of them that hoist, and the generated Kotlin declares no top-level
`metadata` — so it is a decode break, not a test failure.

`Rpc.Pipeline.format_data/2` is the answer: it asks the shared function to
format the payload, takes the payload back out of the envelope, and matches
the `%{data:, metadata:}` shape stage 3 produces so metadata stays nested.
The nesting decision is #24's and is unchanged.

The dependency floor moved to `~> 0.4` for this. 0.4.0 is the first release
whose stage 4 formats a multi-record read; on 0.3.0 the same change returned
internal atom keys for every list and page read and failed twelve tests.

Cost: two wire changes, both deliberate.

An untyped `Ash.Type.Map` no longer has its keys renamed. They are data, not
field names, and renaming them meant a value written as `created_by` could
never be read back under the name it was written with. A typed map still has
its declared field names formatted, which is what makes this a rule rather
than an omission.

A `field_names` override is now honoured, where before both the server and the
generator ignored it. They agreed by doing nothing, so fixing either side
alone would have sent `addressLine1` to a class declaring `address_line_1` —
the #24 and #51 shape, code that compiles and decodes `null`. Both moved
together, and `Resource.Info.client_field_name/3` is the one function both
ask. Input keys are untouched except under an override: the request contract
was snake_case and stays so.

Not fixed, and named here so it is not rediscovered: `Runner` parses `input`
before it knows any field's type, so nested keys inside an untyped map are
still snake_cased on the way in. A key sent as `createdBy` is stored and
returned as `created_by`. Resolving input keys by type means minting atoms for
unknown names, which reopens the atom-table exhaustion #18 closed.

## 2026-09-23 — A parsed client key is a string, and atoms are resolved by name

`Runner.to_snake_case_key/1` returned an atom when `String.to_existing_atom/1`
found one and a string when it did not. One `input`, `filter`, `page`,
`identity` or `getBy` map therefore held `:retry_count` beside `"created_by"`,
and which of the two a key got followed the modules the VM had loaded rather
than the request (#77). The entry below fixed that for the keys inside an
untyped map; the parser itself still returned two types, so the map holding
the attribute did too.

The parser moved to `Rpc.KeyNames` and returns a string for every key. The
atoms it used to return existed to name a known argument, attribute or option,
so `KeyNames.resolve/2` does that lookup against a list the caller already
holds. Four callers need it and each knows its own names: Ash's page options
for `page` (`Ash.Page.page_opts/1` reads `page[:limit]` with atom keys), the
resource's attributes for `identity` (the shared pipeline matches with
`Map.has_key?(identity, :id)`), the DSL's own list for `getBy`, and a `:map`
attribute's declared fields for the keys inside it. `input` and `filter` need
no atoms — `Ash.Changeset.for_create/4` and `Ash.Query.filter_input/2` read
string keys.

Cost: Elixir code that pattern-matches a parsed map inside the request path
now reads `%{"title" => "x"}` where it read `%{title: "x"}`. No wire change —
Jason encodes both spellings identically — so no generated client moves.
`String.to_atom/1` is still called nowhere, so #18 stays closed. The
camelCase-to-snake_case asymmetry (#76) is untouched and stays open: a key
sent as `createdBy` inside an untyped map is still stored as `created_by`.

## 2026-09-16 — Untyped map values never promote a data key to an atom

`Runner.to_snake_case_key/1` (now `Rpc.KeyNames.internal_key/2`) promoted a
key to an atom with
`String.to_existing_atom/1`, which succeeds the moment ANY loaded code has
interned that exact atom, not only this app's own. The paragraph above only
ever measured the safe path: "created_by" and "retry_count" were never atoms
anywhere in the VM when it was written. Upgrading to ash 3.33.4 (#81) pulled
in reactor 1.0.7, whose `Reactor.Error.Invalid.RetriesExceededError` defines a
`:retry_count` struct field, interning that atom at load — so an untyped
`:metadata` attribute holding `retry_count` came back with a mixed
atom/string-keyed map that does not round-trip through JSON the same way
twice.

`Runner.convert_keys_to_atoms/2` (now `Rpc.KeyNames.parse/3`) checks, once it
resolves a key to an
attribute whose type is an unconstrained `Ash.Type.Map`, and stops promoting
keys under it: they are still snake-cased on the way in, per the rule above,
but kept as strings always. This closes the atom-promotion half of the risk
without touching the camelCase-snake_case asymmetry, which stays deliberately
unfixed for the reason given above — resolving it fully means minting atoms
for names Ash never declared, which #18 still forbids. No new atoms are
minted anywhere by this change.

## 2026-09-12 — The manifest module lives here, not in the core

`ash_introspection` builds no manifest because building one needs a Spark DSL
that names the client-facing actions, and that library ships none — the
recorded reason its issue 26 was declined. So `AshKotlinMultiplatform.Manifest`
sits next to `AshKotlinMultiplatform.Rpc`, which already names them. It is a
standalone `use Spark.Dsl` module rather than a domain extension: one domain
cannot see the others, a per-domain manifest would fight itself when the same
resource appears in two `kotlin_rpc` blocks, and a domain transformer has
nowhere to hang a compile-time dependency on the *other* domains — which is
the whole point of the edges.

**Cost.** A consumer now has a module and a config line to declare, and
`mix ash_kotlin_multiplatform.install` exists to write both. Two transformers
and a full reachability walk run on every compile of that module, for output
nothing reads yet (see [risks.md](risks.md)).

## 2026-09-12 — The entrypoint lookups are keyed off `entrypoint.config`

`AshIntrospection.Manifest.Decorator.decorate/3` offers an `:entrypoint_name`
callback and builds a global lookup from it. The callback receives
`(resource, action_name)` and never reads `entrypoint.config`, so it cannot
tell two client-facing operations over one Ash action apart — and this library
has those by design. `AshKotlinMultiplatform.Rpc`'s own moduledoc exposes
`MyApp.Todo`'s `:read` twice, as `list_todos` and `get_todo`. Supplying the
callback makes the decorator raise "two entrypoints claim the client-facing
name" and stops the documented example compiling.

So we pass no `:entrypoint_name`, leave the core's `entrypoint_lookup` empty,
and build `:rpc_action_lookup` and `:typed_query_lookup` in
`Transformers.DecorateManifest` off `entrypoint.config`, which is the only
place a client-facing name exists.

**Cost.** Two lookups this repository maintains instead of one the core
maintains, and a standing constraint: nothing downstream may key an entrypoint
by `{resource, action}`. The constraint is written in the transformer's
moduledoc, where the next reader hits it. A 3-arity callback in the core would
remove the duplication; it was not worth blocking stage 3 on.

## 2026-09-12 — `include_private_relationships?: true` when generating

`Ash.Info.Manifest.Generator.generate/1` defaults it to `false`.
`ash_introspection` shipped stage 1 with the default and its
`ResourceInfo.relationship/3` then answered `nil` for a private `belongs_to`
where `Ash.Resource.Info` answers the relationship;
`ResourceFields.get_field_type_info/3` inherited the bug because it asks
`relationship/3` for a field's type. Passing `true` keeps this library from
repeating it one layer out.

**Cost.** A larger manifest than the client strictly needs — private
relationships are not generated into Kotlin. `Test.Book.editor` is the fixture,
and the test carries an oracle asserting the generator's defaults omit it, so
the assertion cannot pass for the wrong reason.

## 2026-09-12 — The compile edges are measured, not asserted

The `8c07331` edges are the difference between a manifest that tracks its
domains and one that goes stale with no error, and until this PR the claim that
they work rested on a code comment — upstream's. Both are now measured by
tests:

- The domain edge, with `mix xref graph --label compile`, which shows
  `todo.ex` → `test_domain.ex (compile)` → `test_manifest.ex (compile)`. The
  middle link is Ash's, not ours; the test fails with the instruction to add a
  per-resource `module_info/1` edge if Ash ever drops it. None is needed today.
- The config edge, against Elixir's own compiler manifest, which is the file
  `mix` reads to decide what a config change invalidates.

**Cost.** One test shells out to `mix xref` and reads a `_build` file, so it is
coupled to Elixir's compiler-manifest layout and will need updating if that
changes. That is the price of proving the thing rather than asserting it.

One trap worth recording, because it cost a detour and briefly had this branch
claiming upstream's placement was broken: the compile-env entry's shape is
`{app, key_path_list, {:ok, value}}`. Looking for a bare
`{app, :ash_domains, value}` finds nothing and reads as a missing edge.
`handle_opts/1` registers the edge correctly through `Code.eval_quoted`,
exactly as upstream has it.

## 2026-09-12 — No `SpecCache`

Upstream added a `persistent_term` spec cache in `199f9cd` and deleted it in
`b7104a8`, moving the lookups onto the manifest module's persisted Spark DSL
state. `Spark.Dsl.Extension.get_persisted/3` reads a compiled module attribute,
which is already free at runtime, so a second cache would buy nothing and add a
second thing to go stale. Not ported.

## 2026-09-12 — `get_by` is a read-only option, enforced at compile time

`get_by` names the fields a client sends to select one record. The generator
emits that field for read actions only
(`Rpc.Codegen.Helpers.ConfigBuilder.get_action_context/3`), so the other half of
the DSL had two ways to go: teach the generator to emit `getBy` for writes, or
refuse the combination. `Rpc.Verifiers.VerifyIdentities` now refuses it (#69).

Why: an update or destroy already has a lookup key — `identities` — and a
create looks up nothing. A second lookup mechanism on the same action would
give two DSL options that select a record, with no rule saying which wins. The
old behaviour was worse than either: the action compiled, shipped a client that
could not send the field, and failed every call with `{:missing_get_by_fields,
...}`.

Cost: a project that set `get_by` on a write and never called the action now
fails to compile. That build was already broken; it just had not been run yet.

## 2026-09-17 — Codegen reads embedded types from a required manifest

Both generators declare one class per `kind: :embedded_resource` entry in the
persisted manifest's `types`, through `Manifest.embedded_resources/1` (#84).
They used to walk the RPC resources' public attributes one level deep. With
nine embedded fixtures that walk found 1 type and the manifest found 8, and
the generated Kotlin named `Edition`, `UnionNote` and `SummaryOpts` without
declaring them.

We accept the widening, as `ash_typescript` does. `Cover`, `Summary`,
`SecretNote` and `VaultSeal` now get classes although no generated data class
field names them; the Kotlin compile gate checks every one. The alternative, a
deeper walk of our own, is the code `ash_introspection#23` exists to delete.

The manifest is now required. `Manifest.manifest_module/0` raises when
`config :ash_kotlin_multiplatform, :manifest` is unset, naming the config line
and `mix igniter.install ash_kotlin_multiplatform`. There is no fallback to the
live walk, because a fallback would keep the defect it replaces.

**Cost.** Breaking: an app without the config key cannot generate code, so
this ships as 0.2.0. `BuildManifest` compiles every domain resource before
generating, which widens the deadlock surface in [risks.md](risks.md). A type
reached only through a `first` aggregate is still missing, because Ash leaves
the aggregate's `type` `nil` at build time. The embedded classes in a
generated file reorder once, sorted by module instead of `MapSet` order.

*Settled 2026-09-18.* That last cost is paid. ash 3.33.6 fills the
aggregate's `type` before the walk runs (ash-project/ash#2950, for
ash-project/ash#2949), so the route this decision could not cover now
resolves upstream where it belongs. `mix.exs` floors ash there and
`Test.PrivateMeta` gets a class (#100).

## 2026-09-17 — A generic action's return is classified once, in `Resource.Info`

`Resource.Info.returned_resource/1` names the resource a generic action
returns: a bare resource module, a `:struct` whose `instance_of` is a
resource, a NewType over either, or a list of any of them. Codegen names the
Kotlin class from it (#87), and `Rpc.Runner` takes the default fields of a
request with no `fields` from it (#88). Before #88 the runner took the owner's
attributes, so `summarize_book` sent Book's five keys, all null, and Kotlin
decoded `Summary(label=null)` with no error.

It is not ash_introspection's `action_returns_field_selectable_type?/1`. That
function has no branch for a bare resource module, so it answers
`{:error, :not_field_selectable_type}` for `Book.summarize`, which returns
the embedded `Summary`. The runtime `FieldSelector.select_fields/5` does take
that branch. Fixing the shared classifier first would need an
ash_introspection release before 0.2.0.

A generic action returning a map, struct or keyword list with declared
`fields` defaults to those names, for the same reason. A tuple with declared
`fields` takes the positional template `FieldSelector.select_tuple_fields/4`
builds for an empty request. The map came in #88; the other three sent Book's
null keys until #95. An untyped container and a scalar keep their responses.

A union return is the one case the runner cannot fill in, so since #96 it
sends an EMPTY template. Which member is active is decided at result time by
`%Ash.Union{type:}`, and the same action can answer with a different member
each call, so there is no set of field names to send ahead of the result. An
empty template is what
`AshIntrospection.Rpc.ResultProcessor.extract_union_value/4` reads as "this
member's declared fields", so each member gets exactly what the paragraph
above gives its own type: a resource member its public attributes, a typed map
member its declared fields, a scalar member the value. Sending Book's
attribute names instead returned `nil` for a single union and `[]` for a list,
whatever the member was.

That empty template needs `ash_introspection` 0.5.1, which is the floor in
`mix.exs`. On 0.5.0 the same request returns `nil` with or without `fields`
(ash_introspection#84).

**Cost.** Breaking on the wire for a client that omitted `fields` on such an
action, so it ships in 0.2.0 with #84 and #87. `FieldSelector` still carries
its own classifier, and the two disagree on embedded resources until
ash_introspection gains the branch. When it does, `returned_resource/1` can
delegate to it.

## 2026-09-19 — Two pipeline configs: one for compiling, one for requests

The request path reads the compile-time manifest
(`ash_introspection#23` stage 5a, PR 4), and the config it reads it from is a
second builder rather than a widened `build_config/0`.

`AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest` calls
`Rpc.Pipeline.build_config/0` to build the config it decorates the manifest
WITH, at `decorate_manifest.ex:66`, while the manifest module is still
compiling. `build_config/0` reading
`config :ash_kotlin_multiplatform, manifest:` would therefore ask the module
being compiled for its own persisted state — a cycle with no useful answer,
and the decoration is exactly what does not exist yet at that point. The same
argument covers the compile-time verifiers and both code generators, which call
the readers before any manifest exists.

So `request_config/0` and `request_config/1` are `build_config/0` and `/1` plus
`:manifest` and `:manifest_namespace`, and the five request entry points take
them: `Runner.execute_action/7`, `Runner.field_selector_config/1`,
`Pipeline.execute_ash_action/1`, `Pipeline.process_result/2` and
`Pipeline.format_data/2`. `build_config/0` keeps exactly one caller that must
never see a manifest, and a test asserts the key is absent so merging the two
fails a test rather than a build.

### The manifest travels bare, not as a prepared `Source`

`AshIntrospection.ResourceInfo` reads through an
`AshIntrospection.ResourceInfo.Source`, which is two lookup maps built from the
manifest. A consumer can persist a prepared `Source` once, at compile time, or
hand over the bare `%Ash.Info.Manifest{}` and let each entry point prepare it.
This library hands it over bare.

Measured on 2026-09-19 against this repo's test manifest (7 resources, 11
types), median of 200 batches of 1000 calls:

| Call | Cost |
| ---- | ---- |
| `ResourceInfo.prepare/2` — one `Source` | 250 ns |
| `ResourceInfo.normalize_config/1` | 323 ns |
| `Pipeline.request_config/0` | 140 ns |
| `Pipeline.build_config/0` | 81 ns |

Four prepares per request is about 1.0-1.3 us. A full `run_action/3` on the
same machine is 41 us for a five-record read with no `fields` and 162 us for
one with a nested relationship, so the prepares are 1-3% of a request — and
the end-to-end medians did not separate from `main` across two runs (36/148/53
us against 44/199/65 us, then 41/162/59 against 41/163/55; the spread within
one side is larger than the difference between them).

The reason is not the number. Persisting a prepared `Source` would put an
`ash_introspection` internal struct in this library's own persisted DSL state,
so a change to `Source`'s shape would become a manifest recompile the consumer
has no way to notice — the same class of staleness the compile edges exist to
prevent. `ash_introspection#23` stage 5a's PR 6 revisits the hand-over with
these numbers in hand.

**Cost.** A stale or wrongly scoped manifest now costs requests, not only
codegen: an `rpc_action` the manifest does not carry answers
`action_not_found` where the live domain scan found it. That is the point of
the change and it is what `runner_manifest_source_test.exs` asserts, but a
consumer who never recompiled their manifest module meets it as a 404 rather
than a short type list. `run_action/3`'s `otp_app` argument now selects
nothing, because the manifest config names one module for the library. The
argument stays on the public entry points.
