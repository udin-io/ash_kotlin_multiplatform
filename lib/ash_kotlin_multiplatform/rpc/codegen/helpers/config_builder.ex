# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.Helpers.ConfigBuilder do
  @moduledoc """
  Builds Kotlin configuration field definitions for RPC functions.

  Configuration fields define the parameters that can be passed to RPC functions,
  including tenant, primary key, input, pagination, filters, and metadata fields.
  """

  alias AshKotlinMultiplatform.Codegen.TypeMapper
  alias AshKotlinMultiplatform.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.MetadataTypes
  alias AshIntrospection.Helpers

  @doc """
  Gets the action context - a map of values indicating what features the action supports.

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash action (possibly augmented with RPC settings)
    * `rpc_action` - The RPC action configuration

  ## Returns

  A map with the following keys:
  - `:requires_tenant` - Whether the action requires a tenant parameter
  - `:identities` - List of identity atoms for record lookup (update/destroy actions)
  - `:supports_pagination` - Whether the action supports pagination (list reads)
  - `:supports_filtering` - Whether the action supports filtering (list reads)
  - `:supports_sorting` - Whether the action supports sorting (list reads)
  - `:get_by` - Fields the client sends to select one record (`[]` when none)
  - `:action_input_type` - Whether the input is :none, :required, or :optional
  - `:is_get_action` - Whether this is a get action (returns single or null)

  `rpc_action` is read with `Map.get/3` throughout rather than by struct field,
  because the codegen tests pass a bare map for actions that set no options.
  """
  def get_action_context(resource, action, rpc_action) do
    # Check both Ash's native get? and RPC's get?/get_by options
    ash_get? = action.type == :read and Map.get(action, :get?, false)
    rpc_get? = Map.get(rpc_action, :get?, false)
    get_by = if action.type == :read, do: Map.get(rpc_action, :get_by) || [], else: []

    is_get_action = ash_get? or rpc_get? or get_by != []
    list_read? = action.type == :read and not is_get_action

    identities =
      if action.type in [:update, :destroy] do
        Map.get(rpc_action, :identities, [:_primary_key])
      else
        []
      end

    %{
      requires_tenant: AshKotlinMultiplatform.requires_tenant_parameter?(resource),
      identities: identities,
      supports_pagination: list_read? and ActionIntrospection.action_supports_pagination?(action),
      supports_filtering: list_read? and Map.get(rpc_action, :enable_filter?, true),
      supports_sorting: list_read? and Map.get(rpc_action, :enable_sort?, true),
      get_by: get_by,
      action_input_type: ActionIntrospection.action_input_type(resource, action),
      is_get_action: is_get_action
    }
  end

  @doc """
  Generates a Kotlin config data class for an RPC action.

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash action
    * `rpc_action` - The RPC action configuration
    * `rpc_action_name` - The name of the RPC action

  ## Returns

  A string containing the Kotlin data class definition.
  """
  def generate_config_type(resource, action, rpc_action, rpc_action_name) do
    rpc_action_name_pascal = Helpers.snake_to_pascal_case(rpc_action_name)
    context = get_action_context(resource, action, rpc_action)

    fields = []

    # Add tenant field if required
    fields =
      if context.requires_tenant do
        fields ++ [{:tenant, "String", false}]
      else
        fields
      end

    # Add identity field if needed for update/destroy
    fields =
      if context.identities != [] do
        fields ++ [{:identity, build_identity_type(resource, context.identities), false}]
      else
        fields
      end

    # Add the get_by lookup for a single-record read
    fields =
      if context.get_by != [] do
        fields ++ [{:get_by, "#{rpc_action_name_pascal}GetBy", false}]
      else
        fields
      end

    # Add input field based on input type
    fields =
      case context.action_input_type do
        :required ->
          fields ++ [{:input, "#{rpc_action_name_pascal}Input", false}]

        :optional ->
          fields ++ [{:input, "#{rpc_action_name_pascal}Input?", true, "null"}]

        :none ->
          fields
      end

    # Add fields selection field for non-destroy actions
    fields =
      if action.type != :destroy do
        fields ++ [{:fields, "List<Any>", true, "emptyList()"}]
      else
        fields
      end

    # Add filter and sort for list reads
    fields =
      if context.supports_filtering do
        fields ++ [{:filter, "Map<String, JsonElement>?", true, "null"}]
      else
        fields
      end

    fields =
      if context.supports_sorting do
        fields ++ [{:sort, "String?", true, "null"}]
      else
        fields
      end

    # Add pagination config for paginated reads
    fields =
      if context.supports_pagination do
        fields ++ [{:page, "Map<String, JsonElement>?", true, "null"}]
      else
        fields
      end

    # Add metadata fields selector when the action exposes metadata (mirrors the
    # has_metadata check in FunctionCore.build_execution_function_shape/5 — the two
    # must stay in sync, or the emitted function body references a config property
    # that was never declared on the class).
    fields =
      if MetadataTypes.metadata_enabled?(
           MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
         ) do
        fields ++ [{:metadata_fields, "List<String>?", true, "null"}]
      else
        fields
      end

    # Add headers field
    fields = fields ++ [{:headers, "Map<String, String>", true, "emptyMap()"}]

    # Generate the data class
    field_defs =
      Enum.map(fields, fn
        {name, type, true, default} ->
          "    val #{Helpers.snake_to_camel_case(name)}: #{type} = #{default}"

        {name, type, true} ->
          "    val #{Helpers.snake_to_camel_case(name)}: #{type}? = null"

        {name, type, false} ->
          "    val #{Helpers.snake_to_camel_case(name)}: #{type}"
      end)

    """
    #{build_get_by_type(resource, context.get_by, rpc_action_name_pascal)}data class #{rpc_action_name_pascal}Config(
    #{Enum.join(field_defs, ",\n")}
    )
    """
  end

  # The lookup fields of a single-record read, as their own @Serializable class
  # rather than a Map<String, JsonElement>: the server requires exactly these
  # fields and rejects anything else, so a client that has to assemble the map by
  # hand learns at runtime what the compiler could have told it.
  #
  # @SerialName carries the resource's own field name, matching
  # InputTypes.generate_input_type/2 — `Runner` snake-cases every incoming key,
  # so both spellings arrive, and emitting one keeps the two request payloads
  # spelled the same way on the wire.
  defp build_get_by_type(_resource, [], _pascal_name), do: ""

  defp build_get_by_type(resource, get_by, pascal_name) do
    field_defs =
      Enum.map_join(get_by, ",\n", fn field_name ->
        attribute = Ash.Resource.Info.attribute(resource, field_name)
        kotlin_type = TypeMapper.get_kotlin_type_for_type(attribute.type, attribute.constraints)
        camel_name = Helpers.snake_to_camel_case(field_name)
        serial_name = Atom.to_string(field_name)

        annotation =
          if serial_name == camel_name, do: "", else: "    @SerialName(\"#{serial_name}\")\n"

        "#{annotation}    val #{camel_name}: #{kotlin_type}"
      end)

    """
    @Serializable
    data class #{pascal_name}GetBy(
    #{field_defs}
    )

    """
  end

  @doc """
  Builds the Kotlin type for an identity field.
  """
  def build_identity_type(resource, identities) do
    # For simplicity, if there's only primary key identity, use the primary key type
    # Otherwise, use a generic type
    case identities do
      [:_primary_key] ->
        primary_key_attrs = Ash.Resource.Info.primary_key(resource)

        if Enum.count(primary_key_attrs) == 1 do
          attr_name = Enum.at(primary_key_attrs, 0)
          attr = Ash.Resource.Info.attribute(resource, attr_name)
          TypeMapper.get_kotlin_type_for_type(attr.type, attr.constraints || [])
        else
          # Composite primary key - use a Map
          "Map<String, JsonElement>"
        end

      _ ->
        # Multiple identities - use a generic type
        "JsonElement"
    end
  end
end
