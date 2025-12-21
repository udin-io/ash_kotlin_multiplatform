# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

- Fixed GitHub URLs to point to correct repository (udin-io/ash_kotlin_multiplatform)

## [0.1.0] - 2025-12-21

> **Alpha Release** - This is an early alpha release. The API may change between versions.

### Added

- Initial release of AshKotlinMultiplatform
- `AshKotlinMultiplatform.Resource` extension for resource-level Kotlin configuration
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
