# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Binary payloads on the generated Phoenix channel client.
  `PhoenixChannel.pushBinary/3` and `AshRpcChannel.pushBinary/3` send a
  `ByteArray` as a Phoenix binary frame, which the server receives as
  `{:binary, data}` in `handle_in/3`; `onBinary/2` and `offBinary/1` bind
  incoming binary events, and `Push.awaitBinary/0`, `receiveBinary/2` and
  `awaitPayload/0` read a binary reply. Incoming binary frames were
  previously dropped by the socket's receive loop. The JSON path is
  unchanged: `push`, `on`, `receive` and `await` keep their signatures.

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
