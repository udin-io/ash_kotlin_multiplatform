# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.InputTypes do
  @moduledoc """
  Generates Kotlin input types for Ash actions.

  Creates data classes that represent the input parameters for each RPC action,
  with proper type mapping and serialization annotations.
  """

  alias AshKotlinMultiplatform.Codegen.TypeMapper
  alias AshIntrospection.Helpers

  @doc """
  Generates input types for all RPC actions in the given domain configuration.
  """
  def generate_input_types(rpc_configs) do
    rpc_configs
    |> Enum.flat_map(fn %{resource: resource, rpc_actions: actions} ->
      Enum.map(actions, fn action ->
        generate_input_type(resource, action)
      end)
    end)
    |> Enum.join("\n\n")
  end

  @doc """
  Generates a Kotlin input data class for a specific action.

  Combines both action arguments and accepted attributes to generate
  the complete input type for create/update actions.
  """
  def generate_input_type(resource, %{name: rpc_name, action: action_name}) do
    action = Ash.Resource.Info.action(resource, action_name)

    if action do
      input_class_name = "#{Helpers.snake_to_pascal_case(rpc_name)}Input"

      # Get all inputs: arguments + accepted attributes
      all_inputs = get_all_inputs(resource, action)

      fields =
        all_inputs
        |> Enum.map(fn input -> generate_input_field(input, action, resource) end)
        |> Enum.join(",\n    ")

      if fields == "" do
        # Empty input class
        "@Serializable\nclass #{input_class_name}"
      else
        """
        @Serializable
        data class #{input_class_name}(
            #{fields}
        )
        """
      end
    else
      # Fallback for missing action
      input_class_name = "#{Helpers.snake_to_pascal_case(rpc_name)}Input"

      "@Serializable\nclass #{input_class_name}"
    end
  end

  # Gets all inputs for an action: public arguments + accepted attributes
  defp get_all_inputs(resource, action) do
    # Get public arguments
    public_arguments =
      action.arguments
      |> Enum.filter(& &1.public?)
      |> Enum.map(fn arg -> {:argument, arg} end)

    # Get accepted attributes (for create/update/destroy actions)
    accepted_attributes =
      (Map.get(action, :accept) || [])
      |> Enum.map(&Ash.Resource.Info.attribute(resource, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn attr -> {:attribute, attr} end)

    public_arguments ++ accepted_attributes
  end

  # Generate field for an input (either argument or attribute)
  defp generate_input_field({:argument, argument}, action, _resource) do
    generate_argument_field(argument, action)
  end

  defp generate_input_field({:attribute, attribute}, action, resource) do
    generate_attribute_field(attribute, action, resource)
  end

  defp generate_argument_field(argument, _action) do
    kotlin_type = get_argument_kotlin_type(argument)
    field_name = format_field_name(argument.name)
    original_name = Atom.to_string(argument.name)

    # Handle SerialName annotation if names differ
    serial_name =
      if original_name != field_name do
        "@SerialName(\"#{original_name}\")\n    "
      else
        ""
      end

    # Handle default values
    {type_with_nullability, default} =
      cond do
        argument.allow_nil? ->
          {"#{kotlin_type}?", " = null"}

        argument.default != nil ->
          {kotlin_type, " = #{format_default_value(argument.default, argument.type)}"}

        true ->
          {kotlin_type, ""}
      end

    "#{serial_name}val #{field_name}: #{TypeMapper.annotate_contextual_types(type_with_nullability)}#{default}"
  end

  defp generate_attribute_field(attribute, action, resource) do
    kotlin_type = get_attribute_kotlin_type(attribute)
    {serial_name, field_name} = input_property_name(resource, attribute.name)

    # Determine if this attribute is required or optional for this action
    is_optional = is_attribute_optional?(attribute, action)

    # Handle nullability and default values
    {type_with_nullability, default} =
      cond do
        is_optional ->
          {"#{kotlin_type}?", " = null"}

        attribute.default != nil ->
          {kotlin_type, " = #{format_default_value(attribute.default, attribute.type)}"}

        attribute.allow_nil? ->
          {"#{kotlin_type}?", " = null"}

        true ->
          {kotlin_type, ""}
      end

    "#{serial_name}val #{field_name}: #{TypeMapper.annotate_contextual_types(type_with_nullability)}#{default}"
  end

  # Determines if an attribute is optional for the given action
  defp is_attribute_optional?(attribute, action) do
    allow_nil_input = Map.get(action, :allow_nil_input, [])
    require_attributes = Map.get(action, :require_attributes, [])

    cond do
      # For update actions, all attributes are optional by default unless explicitly required
      action.type == :update and attribute.name not in require_attributes ->
        true

      # Explicitly allowed to be nil for this action
      attribute.name in allow_nil_input ->
        true

      # Explicitly required for this action
      attribute.name in require_attributes ->
        false

      # Has a default value
      attribute.default != nil ->
        true

      # Allows nil in general
      attribute.allow_nil? ->
        true

      # Otherwise required
      true ->
        false
    end
  end

  defp get_argument_kotlin_type(argument) do
    # Create a pseudo-attribute to reuse TypeMapper
    pseudo_attr = %{
      type: argument.type,
      constraints: argument.constraints || [],
      allow_nil?: false
    }

    TypeMapper.get_kotlin_type(pseudo_attr, nullable: false)
  end

  defp get_attribute_kotlin_type(attribute) do
    # Attributes already have the structure TypeMapper expects
    TypeMapper.get_kotlin_type(attribute, nullable: false)
  end

  defp format_field_name(name) do
    name
    |> Atom.to_string()
    |> Helpers.snake_to_camel_case()
  end

  # The Kotlin property declaration for one accepted attribute:
  # `{annotation, property_name}`.
  #
  # Only a `field_names` override changes anything here. Without one an input
  # field keeps the attribute's own name on the wire — `starts_on`, not
  # `startsOn` — which is what `Runner`'s input parser has always accepted and
  # what the round-trip gate's `inputEncoding` check pins by decoding a literal
  # and re-encoding it unchanged. #71 touches the response contract, not this
  # one, so this stays as it was.
  #
  # With an override the override is the wire key, because the server resolves
  # it too: `Runner`'s input parser consults `field_names` before the generic
  # camelCase parser, so a client sending `address_line_1` and one sending
  # `addressLine1` must not both be generated for the same field.
  #
  # Arguments do not come through here. `field_names` maps resource fields and
  # an action argument is not one; the DSL's separate `argument_names` option
  # covers those.
  defp input_property_name(resource, field_name) do
    wire_name = input_wire_name(resource, field_name)
    property = Helpers.snake_to_camel_case(wire_name)

    if wire_name == property do
      {"", property}
    else
      {"@SerialName(\"#{wire_name}\")\n    ", property}
    end
  end

  defp input_wire_name(resource, field_name) do
    case Keyword.get(
           AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_field_names(resource),
           field_name
         ) do
      nil -> Atom.to_string(field_name)
      override -> to_string(override)
    end
  end

  defp format_default_value(default, _type) when is_binary(default), do: "\"#{default}\""
  defp format_default_value(default, _type) when is_boolean(default), do: to_string(default)
  defp format_default_value(default, _type) when is_integer(default), do: to_string(default)
  defp format_default_value(default, _type) when is_float(default), do: to_string(default)
  defp format_default_value(nil, _type), do: "null"

  defp format_default_value(default, _type) when is_atom(default) do
    # For enum values, we'd need the enum class name
    "\"#{default}\""
  end

  defp format_default_value(_default, _type), do: "null"
end
