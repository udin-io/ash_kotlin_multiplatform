# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.FunctionGenerators.FunctionCore do
  @moduledoc """
  Builds the common "shape" of RPC functions, independent of transport.

  This module extracts all the shared logic between HTTP and Channel function generation,
  returning a structured map that renderers use to emit transport-specific Kotlin code.
  """

  alias AshKotlinMultiplatform.Rpc.Codegen.Helpers.{ActionIntrospection, ConfigBuilder}
  alias AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.MetadataTypes
  alias AshIntrospection.Helpers

  @doc """
  Builds the execution function shape for both HTTP and Channel transports.

  Returns a map containing:
  - Basic metadata (resource, action, names, context)
  - Field selection info (has_fields)
  - Pagination info
  - Metadata info
  """
  def build_execution_function_shape(resource, action, rpc_action, rpc_action_name, opts \\ []) do
    transport = Keyword.get(opts, :transport, :http)

    rpc_action_name_pascal = Helpers.snake_to_pascal_case(rpc_action_name)
    resource_name = build_resource_type_name(resource)
    context = ConfigBuilder.get_action_context(resource, action, rpc_action)

    # Check metadata configuration
    has_metadata =
      MetadataTypes.metadata_enabled?(
        MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
      )

    # Determine field selection capabilities
    has_fields = action.type != :destroy

    is_optional_pagination =
      action.type == :read and
        not context.is_get_action and
        ActionIntrospection.action_supports_pagination?(action) and
        not ActionIntrospection.action_requires_pagination?(action) and
        has_fields

    %{
      resource: resource,
      action: action,
      rpc_action: rpc_action,
      rpc_action_name: rpc_action_name,
      rpc_action_name_pascal: rpc_action_name_pascal,
      resource_name: resource_name,
      context: context,
      has_fields: has_fields,
      has_metadata: has_metadata,
      is_optional_pagination: is_optional_pagination,
      is_mutation: action.type in [:create, :update],
      transport: transport
    }
  end

  @doc """
  Builds the validation function shape for both HTTP and Channel transports.

  Validation functions are simpler - they don't have field selection, pagination, etc.
  They just validate input and return validation errors.
  """
  def build_validation_function_shape(resource, action, rpc_action, rpc_action_name, _opts \\ []) do
    rpc_action_name_pascal = Helpers.snake_to_pascal_case(rpc_action_name)
    context = ConfigBuilder.get_action_context(resource, action, rpc_action)

    %{
      resource: resource,
      action: action,
      rpc_action_name: rpc_action_name,
      rpc_action_name_pascal: rpc_action_name_pascal,
      context: context
    }
  end

  @doc """
  Builds the Kotlin resource type name for a resource.
  """
  def build_resource_type_name(resource) do
    case AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_type_name(resource) do
      nil ->
        resource
        |> Module.split()
        |> List.last()

      name ->
        name
    end
  rescue
    _ ->
      resource
      |> Module.split()
      |> List.last()
  end

  @doc """
  Determines the Kotlin type an action's response `data` decodes into.

  This is the `T` in the `RpcResult<T>` the generated function returns, so each
  branch has to name the shape `AshKotlinMultiplatform.Rpc.Runner` actually
  sends, not the shape the action name suggests. Three of them are not obvious,
  and each was measured against a real response before it was written here:

  * **A destroy returns the destroyed record**, not a boolean.
    `AshIntrospection.Rpc.Pipeline.execute_destroy_action/3` bulk-destroys with
    `return_records?: true` and hands back `records: [record]`.
  * **A read that supports pagination returns `AshPage<T>`**, which reads both
    the bare list and the page object — see
    `AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.PaginationTypes`. Ash 3
    defaults every read to offset and keyset pagination, so this is the common
    branch, not the exotic one.
  * **A mutation that exposes metadata returns `AshMetadata<T, M>`**, because
    `AshIntrospection.Rpc.Pipeline.add_mutation_metadata/3` wraps the record —
    see `AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.MetadataTypes`. A
    read does not wrap; it merges the metadata into each record instead.

  A get action keeps the resource type rather than a nullable one: `data` is
  already `T?` on `RpcResult`, so `Resource?` would only add a second question
  mark.

  Returns `JsonElement` for any shape this cannot name — a generic action
  returning a map, or an Ash type the mapper does not recognise.
  kotlinx-serialization has no serializer for `Any` and never will, so
  `JsonElement` is what an untyped shape takes everywhere in this generator
  (#51).
  """
  def determine_return_type(shape) do
    shape
    |> data_type()
    |> wrap_in_metadata_envelope(shape)
  end

  defp data_type(%{action: %{type: :action} = action, resource_name: resource_name}) do
    case ActionIntrospection.action_returns_field_selectable_type?(action) do
      {:ok, :resource, _} -> resource_name
      {:ok, :array_of_resource, _} -> "List<#{resource_name}>"
      _ -> "JsonElement"
    end
  end

  defp data_type(%{action: %{type: :read}, context: context, resource_name: resource_name}) do
    cond do
      context.is_get_action -> resource_name
      context.supports_pagination -> "AshPage<#{resource_name}>"
      true -> "List<#{resource_name}>"
    end
  end

  defp data_type(%{action: %{type: type}, resource_name: resource_name})
       when type in [:create, :update, :destroy],
       do: resource_name

  defp data_type(_shape), do: "JsonElement"

  defp wrap_in_metadata_envelope(data_type, %{has_metadata: true, action: %{type: type}} = shape)
       when type in [:create, :update, :destroy] do
    "AshMetadata<#{data_type}, #{shape.rpc_action_name_pascal}Metadata>"
  end

  defp wrap_in_metadata_envelope(data_type, _shape), do: data_type
end
