# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.MetadataTypes do
  @moduledoc """
  Generates Kotlin metadata types for RPC actions.

  Metadata types define the shape of metadata that can be returned from RPC actions.
  Actions can expose specific metadata fields via the `show_metadata` option.
  """

  alias AshKotlinMultiplatform.Codegen.TypeMapper
  alias AshIntrospection.Helpers

  @doc """
  Gets the list of metadata fields that should be exposed for an RPC action.

  ## Parameters

    * `rpc_action` - The RPC action configuration
    * `ash_action` - The underlying Ash action

  ## Returns

  A list of metadata field names (atoms) that should be exposed.

  ## Examples

      # No metadata override - expose all metadata fields
      iex> get_exposed_metadata_fields(%{}, %{metadata: [%{name: :total_count}]})
      [:total_count]

      # Empty list - expose no metadata fields
      iex> get_exposed_metadata_fields(%{show_metadata: []}, %{metadata: [%{name: :total_count}]})
      []

      # Specific fields - expose only listed fields
      iex> get_exposed_metadata_fields(%{show_metadata: [:total_count]}, %{metadata: [...]})
      [:total_count]
  """
  def get_exposed_metadata_fields(rpc_action, ash_action) do
    show_metadata = Map.get(rpc_action, :show_metadata, nil)

    case show_metadata do
      nil -> Enum.map(Map.get(ash_action, :metadata, []), & &1.name)
      false -> []
      [] -> []
      field_list when is_list(field_list) -> field_list
    end
  end

  @doc """
  Checks if metadata is enabled for an action based on exposed fields.

  ## Parameters

    * `exposed_fields` - List of metadata fields that are exposed

  ## Returns

  Boolean indicating if metadata is enabled (has at least one exposed field).
  """
  def metadata_enabled?(exposed_fields) do
    not Enum.empty?(exposed_fields)
  end

  @doc """
  Generates the Kotlin metadata data class for an RPC action.

  Returns an empty string if no metadata fields are exposed.

  ## Parameters

    * `action` - The Ash action
    * `rpc_action` - The RPC action configuration
    * `rpc_action_name` - The name of the RPC action

  ## Returns

  A string containing the Kotlin metadata type definition, or an empty string if no metadata is exposed.
  """
  def generate_action_metadata_type(action, rpc_action, rpc_action_name) do
    exposed_fields = get_exposed_metadata_fields(rpc_action, action)
    rpc_action_name_pascal = Helpers.snake_to_pascal_case(rpc_action_name)

    if metadata_enabled?(exposed_fields) do
      all_metadata_fields = Map.get(action, :metadata, [])

      metadata_fields_to_include =
        Enum.filter(all_metadata_fields, fn metadata_field ->
          metadata_field.name in exposed_fields
        end)

      metadata_field_defs =
        Enum.map(metadata_fields_to_include, fn metadata_field ->
          kotlin_type = TypeMapper.get_kotlin_type_for_type(metadata_field.type, metadata_field.constraints || [])

          optional = Map.get(metadata_field, :allow_nil?, true)

          # Check for mapped metadata field names
          metadata_field_names = Map.get(rpc_action, :metadata_field_names, [])
          mapped_name = Keyword.get(metadata_field_names, metadata_field.name, metadata_field.name)
          formatted_name = Helpers.snake_to_camel_case(mapped_name)

          # Add @SerialName if the formatted name differs from the original
          serial_name_annotation =
            if to_string(mapped_name) != to_string(metadata_field.name) do
              "    @SerialName(\"#{metadata_field.name}\")\n"
            else
              ""
            end

          if optional do
            "#{serial_name_annotation}    val #{formatted_name}: #{kotlin_type}? = null"
          else
            "#{serial_name_annotation}    val #{formatted_name}: #{kotlin_type}"
          end
        end)

      """
      @Serializable
      data class #{rpc_action_name_pascal}Metadata(
      #{Enum.join(metadata_field_defs, ",\n")}
      )
      """
    else
      ""
    end
  end

  @doc """
  Checks if an action has any metadata that can be exposed.
  """
  def action_has_metadata?(action) do
    case Map.get(action, :metadata, []) do
      [] -> false
      _ -> true
    end
  end
end
