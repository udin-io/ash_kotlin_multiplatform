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
