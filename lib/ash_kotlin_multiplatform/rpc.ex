# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc do
  @moduledoc """
  Spark DSL extension for configuring Kotlin RPC generation on Ash domains.

  This extension allows domains to define which resources and actions
  should be exposed via generated Kotlin client code.

  ## Example

  ```elixir
  defmodule MyApp.Domain do
    use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

    kotlin_rpc do
      resource MyApp.Todo do
        rpc_action :list_todos, :read
        rpc_action :create_todo, :create
        rpc_action :get_todo, :read

        typed_query :my_query, :read,
          fields: ["id", "title"],
          kotlin_result_type_name: "TodoResult",
          kotlin_fields_const_name: "QUERY_FIELDS"
      end
    end
  end
  ```
  """

  defmodule RpcAction do
    @moduledoc """
    Struct representing an RPC action configuration.

    Defines the mapping between a named RPC endpoint and an Ash action.
    """
    defstruct [
      :name,
      :action,
      :read_action,
      :show_metadata,
      :metadata_field_names,
      __spark_metadata__: nil
    ]
  end

  defmodule Resource do
    @moduledoc """
    Struct representing a resource's RPC configuration.

    Contains the resource module and lists of configured RPC actions
    and typed queries for that resource.
    """
    defstruct [:resource, rpc_actions: [], typed_queries: [], __spark_metadata__: nil]
  end

  defmodule TypedQuery do
    @moduledoc """
    Struct representing a typed query configuration.

    Defines a pre-configured query with specific fields and Kotlin types,
    allowing for type-safe, reusable query patterns in the generated RPC client.
    """
    defstruct [
      :name,
      :kotlin_result_type_name,
      :kotlin_fields_const_name,
      :resource,
      :action,
      :fields,
      __spark_metadata__: nil
    ]
  end

  @typed_query %Spark.Dsl.Entity{
    name: :typed_query,
    target: TypedQuery,
    schema: [
      action: [
        type: :atom,
        doc: "The read action on the resource to query"
      ],
      name: [
        type: :atom,
        doc: "The name of the RPC-action"
      ],
      kotlin_result_type_name: [
        type: :string,
        doc: "The name of the Kotlin type for the query result"
      ],
      kotlin_fields_const_name: [
        type: :string,
        doc:
          "The name of the constant for the fields, that can be reused by the client to re-run the query"
      ],
      fields: [
        type: {:list, :any},
        doc: "The fields to query"
      ]
    ],
    args: [:name, :action]
  }

  @rpc_action %Spark.Dsl.Entity{
    name: :rpc_action,
    target: RpcAction,
    describe: """
    Define an RPC action that exposes a resource action to Kotlin clients.

    Metadata fields: Action metadata can be exposed via `show_metadata` option.
    Set to `nil` (default) to expose all metadata fields, `false` or `[]` to disable,
    or provide a list of atoms to expose specific fields.

    Metadata field naming: Use `metadata_field_names` to map invalid metadata field names
    (e.g., `field_1`, `is_valid?`) to valid Kotlin identifiers.
    Example: `metadata_field_names [field_1: :field1, is_valid?: :isValid]`
    """,
    schema: [
      name: [
        type: :atom,
        doc: "The name of the RPC-action"
      ],
      action: [
        type: :atom,
        doc: "The resource action to expose"
      ],
      read_action: [
        type: :atom,
        doc: "The read action to use for update and destroy operations when finding records",
        required: false
      ],
      show_metadata: [
        type: {:or, [nil, :boolean, {:list, :atom}]},
        doc: "Which metadata fields to expose (nil=all, false/[]=none, list=specific fields)",
        default: nil
      ],
      metadata_field_names: [
        type: {:list, {:tuple, [:atom, :atom]}},
        doc: "Map metadata field names to valid Kotlin identifiers",
        default: []
      ]
    ],
    args: [:name, :action]
  }

  @resource %Spark.Dsl.Entity{
    name: :resource,
    target: Resource,
    describe: "Define available RPC-actions for a resource",
    schema: [
      resource: [
        type: {:spark, Ash.Resource},
        doc: "The resource being configured"
      ]
    ],
    args: [:resource],
    entities: [
      rpc_actions: [@rpc_action],
      typed_queries: [@typed_query]
    ]
  }

  @rpc %Spark.Dsl.Section{
    name: :kotlin_rpc,
    describe: """
    Define available RPC-actions for resources in this domain.

    The generated Kotlin code will include:
    - Data classes for each resource
    - Suspend functions for each RPC action
    - Object-oriented API wrappers (e.g., TodoRpc.create())
    - Phoenix Channel client (if enabled)
    """,
    schema: [],
    entities: [
      @resource
    ]
  }

  use Spark.Dsl.Extension, sections: [@rpc]

  @doc """
  Returns the input field formatter for RPC requests.
  """
  def input_field_formatter do
    AshKotlinMultiplatform.input_field_formatter()
  end

  @doc """
  Returns the output field formatter for RPC responses.
  """
  def output_field_formatter do
    AshKotlinMultiplatform.output_field_formatter()
  end
end
