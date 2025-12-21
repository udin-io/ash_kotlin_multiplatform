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
  Determines the return type for an action.
  """
  def determine_return_type(shape) do
    action = shape.action
    resource_name = shape.resource_name
    context = shape.context

    cond do
      action.type == :destroy ->
        "Boolean"

      action.type == :action ->
        # Generic action - check return type
        case ActionIntrospection.action_returns_field_selectable_type?(action) do
          {:ok, :resource, _} ->
            "#{resource_name}"

          {:ok, :array_of_resource, _} ->
            "List<#{resource_name}>"

          {:ok, :typed_map, _} ->
            "Map<String, @Contextual Any?>"

          {:ok, :unconstrained_map, _} ->
            "Map<String, @Contextual Any?>"

          _ ->
            "Map<String, @Contextual Any?>"
        end

      action.type == :read and context.is_get_action ->
        "#{resource_name}?"

      action.type == :read and context.supports_pagination ->
        # Return paginated result
        "Map<String, @Contextual Any?>"

      action.type == :read ->
        "List<#{resource_name}>"

      action.type in [:create, :update] ->
        "#{resource_name}"

      true ->
        "Map<String, @Contextual Any?>"
    end
  end
end
