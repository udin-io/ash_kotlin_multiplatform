# AshKotlinMultiplatform

[![Hex.pm](https://img.shields.io/hexpm/v/ash_kotlin_multiplatform.svg)](https://hex.pm/packages/ash_kotlin_multiplatform)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ash_kotlin_multiplatform)

Generate type-safe Kotlin Multiplatform clients from your Ash resources.

> **Alpha Software Notice**
>
> This library is in **alpha** and under active development. The API may change
> between versions without notice. While functional and tested, it is not yet
> recommended for production use. Please report issues and feedback on
> [GitHub](https://github.com/ash-project/ash_kotlin_multiplatform/issues).

## Features

- **Automatic Kotlin Multiplatform generation** from Elixir Ash resources
- **End-to-end type safety** between backend (Elixir) and frontend (Kotlin)
- **Type-safe RPC client generation** using Ktor and coroutines
- **kotlinx.serialization** integration for JSON handling
- **Phoenix Channel support** for real-time applications
- **Kotlin Multiplatform** support (JVM, iOS, JS, Native)
- **Type-safe filtering** with generated filter types
- **Pagination support** for offset and keyset pagination
- **Validation** with optional javax.validation annotations

## Requirements

- Elixir 1.15+
- Ash 3.7+
- Kotlin 1.9+ (for generated code)
- Ktor 2.0+ (for HTTP client)
- kotlinx.serialization 1.6+ (for JSON)

## Installation

Add `ash_kotlin_multiplatform` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_kotlin_multiplatform, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Add the Resource Extension

Configure your Ash resources with the `AshKotlinMultiplatform.Resource` extension:

```elixir
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    # Optional: customize the Kotlin class name
    type_name "Todo"

    # Optional: map Elixir field names to valid Kotlin identifiers
    field_names %{
      is_done: :isDone,
      created_at: :createdAt
    }
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :is_done, :boolean, default: false
    attribute :created_at, :utc_datetime_usec
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    read :list do
      pagination offset?: true, default_limit: 25
    end
  end
end
```

### 2. Add the Domain Extension

Configure your Ash domain with the `AshKotlinMultiplatform.Rpc` extension to expose actions via RPC:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  kotlin_rpc do
    resource MyApp.Todo do
      # Map RPC endpoint names to Ash actions
      rpc_action :list_todos, :list
      rpc_action :create_todo, :create
      rpc_action :get_todo, :read
      rpc_action :update_todo, :update
      rpc_action :delete_todo, :destroy

      # Optional: define typed queries for common operations
      typed_query :active_todos, :list do
        filter is_done: false
      end
    end
  end

  resources do
    resource MyApp.Todo
  end
end
```

### 3. Generate Kotlin Code

Run the code generation mix task:

```bash
mix ash_kotlin_multiplatform.codegen
```

This generates a Kotlin file (default: `lib/generated/AshRpc.kt`) containing all your types and RPC functions.

## Generated Code Example

The generator produces idiomatic Kotlin code:

```kotlin
package com.myapp.ash

import kotlinx.serialization.*
import kotlinx.datetime.*
import io.ktor.client.*

// Data class with serialization support
@Serializable
data class Todo(
    val id: String,
    val title: String,
    val isDone: Boolean? = false,
    val createdAt: Instant? = null
)

// Configuration for actions
@Serializable
data class CreateTodoConfig(
    val title: String,
    val isDone: Boolean? = null
)

// Sealed class for type-safe results
sealed class CreateTodoResult {
    data class Ok(val data: Todo) : CreateTodoResult()
    data class Error(val errors: List<RpcError>) : CreateTodoResult()
}

// Functional API
suspend fun createTodo(
    client: HttpClient,
    config: CreateTodoConfig
): CreateTodoResult { ... }

// Object-oriented API wrapper
object TodoRpc {
    suspend fun create(client: HttpClient, config: CreateTodoConfig) =
        createTodo(client, config)
    suspend fun list(client: HttpClient, config: ListTodosConfig) =
        listTodos(client, config)
}
```

## Configuration

Configure the generator in your `config/config.exs`:

```elixir
config :ash_kotlin_multiplatform,
  # Output settings
  output_file: "lib/generated/AshRpc.kt",
  package_name: "com.myapp.ash",

  # Code generation options
  generate_phoenix_channel_client: true,
  generate_validation_functions: true,
  generate_filter_types: false,
  generate_validation_annotations: false,

  # Type handling
  datetime_library: :kotlinx_datetime,  # or :java_time
  nullable_strategy: :explicit,         # or :platform

  # RPC endpoints
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",

  # Warnings
  warn_on_missing_rpc_config: true,
  warn_on_non_rpc_references: true
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `output_file` | `"lib/generated/AshRpc.kt"` | Path for generated Kotlin file |
| `package_name` | Auto-generated | Kotlin package name |
| `generate_phoenix_channel_client` | `true` | Generate WebSocket client code |
| `generate_validation_functions` | `true` | Generate input validation functions |
| `generate_filter_types` | `false` | Generate type-safe filter types |
| `generate_validation_annotations` | `false` | Add javax.validation annotations |
| `datetime_library` | `:kotlinx_datetime` | Date/time library (`:kotlinx_datetime` or `:java_time`) |
| `nullable_strategy` | `:explicit` | Nullable handling (`:explicit` for `T?`, `:platform` for `T!`) |
| `run_endpoint` | `"/rpc/run"` | RPC execution endpoint |
| `validate_endpoint` | `"/rpc/validate"` | Validation endpoint |
| `type_mapping_overrides` | `[]` | Custom Ash to Kotlin type mappings |
| `input_field_formatter` | `:camel_case` | Input field name format |
| `output_field_formatter` | `:camel_case` | Output field name format |

## DSL Reference

### Resource Extension (`AshKotlinMultiplatform.Resource`)

```elixir
kotlin_multiplatform do
  # Custom Kotlin class name (default: resource module name)
  type_name "MyCustomName"

  # Map field names to valid Kotlin identifiers
  field_names %{
    elixir_name: :kotlinName
  }

  # Map argument names per action
  argument_names %{
    create: %{from_date: :fromDate}
  }
end
```

### Domain Extension (`AshKotlinMultiplatform.Rpc`)

```elixir
kotlin_rpc do
  resource MyApp.Resource do
    # Map RPC actions to Ash actions
    rpc_action :rpc_name, :ash_action_name

    # Expose metadata fields
    rpc_action :list_items, :read do
      expose_metadata [:total_count]
    end

    # Define typed queries with preset filters
    typed_query :active_items, :read do
      filter status: :active
    end
  end
end
```

## Phoenix Channel Support

When `generate_phoenix_channel_client: true`, the generator creates a full Phoenix Channel client:

```kotlin
// Connect to Phoenix Channel
val channel = AshRpcChannel(
    httpClient = client,
    baseUrl = "ws://localhost:4000/socket/websocket"
)

// Join the RPC topic
channel.join("rpc:lobby")

// Make RPC calls over WebSocket
val result = channel.call<CreateTodoResult>("create_todo", config)
```

## Advanced Features

### Type-Safe Filters

Enable with `generate_filter_types: true`:

```kotlin
val filter = TodoFilter(
    title = StringFilter(contains = "important"),
    isDone = BooleanFilter(eq = false)
)

val result = listTodos(client, ListTodosConfig(filter = filter))
```

### Custom Type Mappings

Map custom Ash types to Kotlin:

```elixir
config :ash_kotlin_multiplatform,
  type_mapping_overrides: [
    {MyApp.Types.Money, "BigDecimal"},
    {MyApp.Types.Email, "String"}
  ]
```

### Lifecycle Hooks

Add hooks for request processing:

```elixir
config :ash_kotlin_multiplatform,
  rpc_action_before_request_hook: "authInterceptor",
  rpc_action_after_request_hook: "responseLogger"
```

## Related Packages

- [ash](https://hex.pm/packages/ash) - The Ash Framework
- [ash_phoenix](https://hex.pm/packages/ash_phoenix) - Phoenix integration for Ash
- [ash_json_api](https://hex.pm/packages/ash_json_api) - JSON:API support for Ash

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.
