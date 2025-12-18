# AshKotlinMultiplatform

Generate type-safe Kotlin Multiplatform clients from your Ash resources.

## Features

- **Automatic Kotlin Multiplatform generation** from Elixir Ash resources
- **End-to-end type safety** between backend (Elixir) and frontend (Kotlin)
- **Type-safe RPC client generation** using Ktor and coroutines
- **kotlinx.serialization** integration for JSON handling
- **Phoenix Channel support** for real-time applications
- **Kotlin Multiplatform** support (JVM, iOS, JS, Native)

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

```elixir
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name "Todo"
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :completed, :boolean, default: false
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
```

### 2. Add the Domain Extension

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  kotlin_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :create_todo, :create
      rpc_action :get_todo, :read
      rpc_action :update_todo, :update
      rpc_action :delete_todo, :destroy
    end
  end

  resources do
    resource MyApp.Todo
  end
end
```

### 3. Generate Kotlin Code

```bash
mix ash_kotlin_multiplatform.codegen
```

## Generated Code Example

```kotlin
package com.myapp.ash

import kotlinx.serialization.*
import kotlinx.datetime.*
import io.ktor.client.*

// Data class
@Serializable
data class Todo(
    val id: String,
    val title: String,
    val completed: Boolean? = false
)

// Functional API
suspend fun createTodo(
    client: HttpClient,
    config: CreateTodoConfig
): CreateTodoResult { ... }

// Object-oriented API
object TodoRpc {
    suspend fun create(client: HttpClient, config: CreateTodoConfig) = createTodo(client, config)
    suspend fun list(client: HttpClient, config: ListTodosConfig) = listTodos(client, config)
}
```

## Configuration

```elixir
config :ash_kotlin_multiplatform,
  output_file: "lib/generated/AshRpc.kt",
  package_name: "com.myapp.ash",
  generate_phoenix_channel_client: true,
  datetime_library: :kotlinx_datetime,
  nullable_strategy: :explicit
```

## Documentation

- [Getting Started Guide](documentation/tutorials/getting-started.md)
- [Configuration Reference](documentation/reference/configuration.md)

## License

MIT License - see [LICENSE](LICENSE) for details.
