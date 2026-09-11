# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking.** Every generated RPC function now returns `RpcResult<T>` named
  for its own action, where it returned the same untyped `RpcResult` with
  `data: JsonElement?` before. `createTodo()` returns `RpcResult<Todo>`,
  `listTodos()` returns `RpcResult<AshPage<Todo>>`, and a mutation that
  exposes metadata returns `RpcResult<AshMetadata<Todo, CreateTodoMetadata>>`.
  Callers replace `result.dataAs<Todo>()` with `result.data`. `dataAs()`
  survives as an extension on `RpcResult<JsonElement>`, which is what the
  Phoenix channel client returns — it takes the action name as a string, so
  it has no type to name.

  Two new types carry the shapes the server chooses per request rather than
  per action. `AshPage<T>` reads both the bare JSON array a read sends
  without a `page` and the offset or keyset page object it sends with one.
  `AshMetadata<T, M>` reads both the `{data, metadata}` envelope a mutation
  sends and the bare record it falls back to when the client narrows the
  metadata away. Both are decoded from real `Rpc.Runner` responses by the CI
  round-trip gate.

  Removed along the way: the `{Action}Result` sealed classes and the
  `{Action}OffsetResult` / `{Action}KeysetResult` / `{Action}PaginatedResult`
  family. No generated function ever referenced them, and neither could have
  decoded what the server sends — the sealed classes need a class
  discriminator `Rpc.Runner` does not write, and the pagination classes
  declare `previousPage: String = ""` against a server that sends `null`.

### Fixed

- A `get?` read that matches no record is a not-found error again when
  codegen warnings are off. `Rpc.Pipeline.build_config/0` wired the pipeline's
  `not_found_error?` to `AshKotlinMultiplatform.warn_on_missing_rpc_config?/0`,
  a codegen-time warning switch, so
  `config :ash_kotlin_multiplatform, warn_on_missing_rpc_config: false` also
  turned every not-found into a successful `null`. It is now per-action, via
  the `not_found_error?` option.

- A destroy's generated return type said `Boolean`. The server returns the
  destroyed record: `AshIntrospection.Rpc.Pipeline.execute_destroy_action/3`
  bulk-destroys with `return_records?: true`. Nothing had noticed, because
  `FunctionCore.determine_return_type/1` had no caller.

### Added

- Six `rpc_action` options, all additive — an `rpc_action` that sets none of
  them behaves exactly as before
  ([#25](https://github.com/udin-io/ash_kotlin_multiplatform/issues/25)). The
  shared core already honoured four of them and the DSL declared none, so
  those branches were unreachable: `AshIntrospection.Rpc.Pipeline` branches on
  `get?`, applies `get_by`, reads `identities` and reads `not_found_error?`
  off the config.

  - `get?` makes a read return one record or nothing instead of a list. The
    generated function's `data` becomes the resource rather than
    `AshPage<Resource>`, and `filter`, `sort` and `page` leave its config.
  - `get_by` names the fields the client sends to select that record, and
    implies `get?`. It generates a `@Serializable` lookup class —
    `GetAuthorGetBy` — so the fields are typed rather than a hand-assembled
    map. The request must carry exactly those fields: a missing one would
    widen the lookup into a `MultipleResults`, and an extra one reaches
    `Ash.Query.do_filter/2`, which reads a map operand as an operator
    expression and turns an exact lookup into an arbitrary predicate.
  - `not_found_error?` (default `true`) chooses between a not-found error and
    a successful `null` when a `get?` read matches nothing.
  - `identities` (default `[:_primary_key]`) lists the identities an update or
    destroy may be addressed by. `[]` means the action takes no identity and
    finds its record some other way, such as from the actor. The verifier that
    checks these names against the resource could never fail before, for want
    of a way to set the option.
  - `enable_filter?` and `enable_sort?` (both default `true`) remove that
    parameter from the generated config class. The server refuses a request
    that sends it anyway rather than dropping it: a stale client would
    otherwise be handed the whole table with no way to know it asked for a
    subset.

  These shape an action's **API surface**, typically to keep a parameter off an
  endpoint that has no use for it. They are **not** authorization — Ash
  policies run on every request regardless of what the DSL exposes.

  `allowed_loads` and `denied_loads` are not here. They need
  `ash_introspection` 0.4.0, whose bump is a separate and breaking change.

- **Breaking for existing users.** Compile-time check that every action
  reachable from the generated Kotlin client is `public?`. Ash documents
  `public? false` as "internal-only and must not be exposed by API
  extensions"; nothing enforced that here, so a `rpc_action` naming a
  non-public action produced a fully typed client function for it. Four
  places are checked: the action a `rpc_action` names, the `read_action` a
  `rpc_action` uses to find records, the action a `typed_query` names, and
  the read action behind a public relationship whose destination is itself
  a Kotlin resource. A project that was exposing a non-public action now
  fails to compile; the error names the offending action and says whether
  to mark it `public? true` or drop the entry.

- Binary payloads on the generated Phoenix channel client.
  `PhoenixChannel.pushBinary/3` and `AshRpcChannel.pushBinary/3` send a
  `ByteArray` as a Phoenix binary frame, which the server receives as
  `{:binary, data}` in `handle_in/3`; `onBinary/2` and `offBinary/1` bind
  incoming binary events, and `Push.awaitBinary/0`, `receiveBinary/2` and
  `awaitPayload/0` read a binary reply. Incoming binary frames were
  previously dropped by the socket's receive loop. The JSON path is
  unchanged: `push`, `on`, `receive` and `await` keep their signatures.

### Fixed

- Union member names that Kotlin cannot compile are now caught at compile
  time. A union attribute is the one place where a name inside
  `constraints` becomes a Kotlin identifier: the sealed class turns each
  member name into a subclass name and each field of a map member into a
  property, so a member `is_valid?` emitted `data class IsValid?(` and a
  member field `ok?` emitted `val ok?:`. Both are rejected now, with the
  attribute, the member and a suggested name in the message. **Breaking
  for existing users** whose union members carry such names — but their
  generated Kotlin did not compile either. Names the generator erases (a
  `:map` attribute's fields, a `:tuple`'s) are deliberately not checked.

- A calculation declared `field?: false` no longer reaches the generated
  Kotlin. Ash keeps such a calculation's value in the record's
  `calculations` map instead of as a struct key, so the generator had
  nowhere to read it from, yet it still appeared in the data class, the
  filter input, type discovery and field-name verification. The last of
  those could fail a build outright: a `field?: false` calculation named
  `score_1` was rejected for a name that never reached Kotlin.

### Changed

- **Breaking on the wire.** The generated channel client now speaks
  Phoenix's v2 protocol. It appends `vsn=2.0.0` on connect and frames text
  messages as the JSON array `[join_ref, ref, topic, event, payload]`.
  Previously it sent no `vsn`, so Phoenix negotiated v1 and the client was
  an unmarked v1 client; v1 has no binary frame at all. The stock Phoenix
  socket offers both versions and needs no change. A host that narrowed its
  socket's `serializer:` option to v1 only must add v2.
- **Breaking on the Kotlin API.** `PhoenixMessage` is no longer
  `@Serializable` — kotlinx.serialization can only emit the v1 object — and
  its `joinRef` field no longer carries `@SerialName("join_ref")`. Encode
  and decode it through the generated `PhoenixSerializer`. `Push.payload` is
  now a `ChannelPayload` rather than a `JsonElement`, so that a binary push
  stops reporting a JSON payload it never had; `Push`'s `JsonElement`
  constructor is kept, so no existing call site changes.

- **Breaking on the Kotlin API.** Every untyped shape is now `JsonElement`
  rather than `@Contextual Any`: untyped maps and keywords are
  `Map<String, JsonElement>`, tuples are `List<JsonElement>`, and a union
  without an owning attribute or an Ash type the mapper does not recognise is
  `JsonElement`. So are the `filter` and `page` config maps,
  `AshRpcError.details` and the action-result `metadata` map. `@Contextual`
  only deferred the failure: kotlinx-serialization has no serializer for
  `Any`, so a field holding a populated map threw
  `SerializationException: Serializer for class 'Any' is not found` at
  runtime. Read a value with the `kotlinx.serialization.json` accessors —
  `todo.metadata?.get("retries")?.jsonPrimitive?.int`. The
  `:untyped_map_type` default changed with it; a configured value naming
  `Any` still compiles.

### Removed

- `AshKotlinMultiplatform.Codegen.ValidationSchemas`, the `with_validation`
  option on `KotlinStatic.generate_imports/1`, and the orphaned
  `generate_validation_annotations?/0` config accessor. Nothing in the
  library called any of the three, and the `javax.validation.constraints`
  annotations they would have emitted are JVM-only, so they could never
  compile in the common Kotlin Multiplatform source set this library
  targets. This is a breaking change on paper, since the module and the
  accessor were public API, but neither was reachable through any
  documented entry point.

### Fixed

- Every encode and decode path in the generated client now shares one `Json`,
  the public `ashRpcJson`, which carries the `SerializersModule`. Only
  `createHttpClient()` did before: `RpcResult.dataAs()` and the Phoenix
  channel client each built their own, and every request payload encoded
  through the `Json` companion, which is `Json.Default` and registers
  nothing. A date or any other `@Contextual` field down those paths threw at
  runtime — including `dataAs()`, the documented way to read a result.
- `Rpc.Runner` now honors the `metadataFields` param the generated Kotlin
  client sends. It narrows the metadata fields the DSL exposes and can never
  widen them: a field the DSL withholds is not returned and raises no error.
  Absent or `null` returns everything the DSL exposes, as before; `[]` returns
  no metadata.

## [0.1.3] - 2025-12-21

### Changed

- Updated contributing link in README

## [0.1.2] - 2025-12-21

### Fixed

- Improved Kotlin codegen for sparse RPC responses
- Simplified RpcResult from sealed class to data class with `dataAs<T>()` helper
- Made AshRpcError fields nullable for flexibility

## [0.1.1] - 2025-12-21

### Fixed

- Fixed GitHub URLs to point to correct repository
  (udin-io/ash_kotlin_multiplatform)

## [0.1.0] - 2025-12-21

> **Alpha Release** - This is an early alpha release. The API may change
> between versions.

### Added

- Initial release of AshKotlinMultiplatform
- `AshKotlinMultiplatform.Resource` extension for resource-level Kotlin
  configuration
  - `type_name` option for custom Kotlin class names
  - `field_names` option for mapping field names to valid Kotlin identifiers
  - `argument_names` option for mapping action argument names
- `AshKotlinMultiplatform.Rpc` extension for domain-level RPC configuration
  - `rpc_action` for exposing Ash actions as RPC endpoints
  - `typed_query` for defining pre-configured queries with filters
  - Metadata exposure control
- Code generation via `mix ash_kotlin_multiplatform.codegen`
  - Kotlin data classes with `@Serializable` annotations
  - Sealed classes for type-safe action results
  - Input configuration types for each action
  - Pagination support (offset and keyset)
  - Optional filter types for type-safe filtering
  - Optional validation functions and annotations
- Phoenix Channel client generation for WebSocket support
- HTTP client generation using Ktor
- kotlinx.serialization integration
- Support for kotlinx-datetime and java.time
- Configurable nullable strategies (explicit vs platform types)
- Field name formatters (camel case conversion)
- Lifecycle hooks for request/response processing
- Verifiers for compile-time validation
  - Field name validation
  - Unique type name validation
  - Action type compatibility validation
  - Resource identity validation

### Dependencies

- Requires Ash 3.7+
- Requires Spark 2.0+
- Requires Elixir 1.15+

[Unreleased]: https://github.com/udin-io/ash_kotlin_multiplatform/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/udin-io/ash_kotlin_multiplatform/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/udin-io/ash_kotlin_multiplatform/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/udin-io/ash_kotlin_multiplatform/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/udin-io/ash_kotlin_multiplatform/releases/tag/v0.1.0
