# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
