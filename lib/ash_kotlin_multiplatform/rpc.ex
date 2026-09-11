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

        rpc_action :get_todo, :read do
          get_by [:id]
        end

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

    The defaults here are the shape the client had before any of these options
    existed, so an `rpc_action` that sets none of them behaves exactly as it did:
    a read returns a list and accepts `filter` and `sort`, an update or destroy
    is found by primary key, and a `get?` read that matches nothing is an error.
    """
    defstruct [
      :name,
      :action,
      :read_action,
      :show_metadata,
      :metadata_field_names,
      identities: [:_primary_key],
      get?: false,
      get_by: [],
      not_found_error?: true,
      enable_filter?: true,
      enable_sort?: true,
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

    Single-record reads: `get?` makes a read return one record or nothing instead
    of a list, and `get_by` names the fields the client sends to select it.
    `get_by` implies `get?`. The generated function returns a nullable resource
    and drops `filter`, `sort` and `page` from its config.

        rpc_action :get_author, :read do
          get_by [:id]
        end

    Record lookup for writes: `identities` lists the identities an update or
    destroy may be addressed by. `[:_primary_key]` (the default) means the
    primary key; a named identity must be defined on the resource; `[]` means
    the action takes no identity at all and finds its record some other way,
    such as from the actor.

    Read surface: `enable_filter?` and `enable_sort?` both default to `true`.
    Setting either to `false` removes that parameter from the generated config
    class and makes the server reject a request that sends it anyway — a stale
    client is told, rather than quietly handed the unfiltered table.

    These options shape the API surface of an action. They are **not**
    authorization. Ash policies run on every request regardless of what the DSL
    exposes, and narrowing the surface here neither adds nor removes a check.
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
      ],
      identities: [
        type: {:list, :atom},
        doc:
          "Identities an update or destroy may be addressed by. `:_primary_key` names the primary key; `[]` means the action takes no identity",
        default: [:_primary_key]
      ],
      get?: [
        type: :boolean,
        doc: "Return a single record or nothing instead of a list. Read actions only",
        default: false
      ],
      get_by: [
        type: {:wrap_list, :atom},
        doc: "Fields the client sends to select one record. Implies `get?`. Read actions only",
        default: []
      ],
      not_found_error?: [
        type: :boolean,
        doc: "Whether a `get?` read matching no record is an error rather than a null result",
        default: true
      ],
      enable_filter?: [
        type: :boolean,
        doc: "Whether the client may send `filter` on a list read",
        default: true
      ],
      enable_sort?: [
        type: :boolean,
        doc: "Whether the client may send `sort` on a list read",
        default: true
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

  use Spark.Dsl.Extension,
    sections: [@rpc],
    verifiers: [
      AshKotlinMultiplatform.Rpc.Verifiers.VerifyPublicActions,
      AshKotlinMultiplatform.Rpc.Verifiers.VerifyIdentities,
      AshKotlinMultiplatform.Rpc.Verifiers.VerifyActionTypes
    ]

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
