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
  """
  def generate_input_type(resource, %{name: rpc_name, action: action_name}) do
    action = Ash.Resource.Info.action(resource, action_name)

    if action do
      input_class_name = "#{Helpers.snake_to_pascal_case(rpc_name)}Input"

      arguments =
        action.arguments
        |> Enum.map(&generate_argument_field/1)
        |> Enum.join(",\n    ")

      if arguments == "" do
        # Empty input class
        "@Serializable\nclass #{input_class_name}"
      else
        """
        @Serializable
        data class #{input_class_name}(
            #{arguments}
        )
        """
      end
    else
      # Fallback for missing action
      input_class_name = "#{Helpers.snake_to_pascal_case(rpc_name)}Input"

      "@Serializable\nclass #{input_class_name}"
    end
  end

  defp generate_argument_field(argument) do
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

    "#{serial_name}val #{field_name}: #{type_with_nullability}#{default}"
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

  defp format_field_name(name) do
    name
    |> Atom.to_string()
    |> Helpers.snake_to_camel_case()
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
