# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.ResourceSchemas do
  @moduledoc """
  Generates Kotlin data classes, enum classes, and sealed classes from Ash resources.

  This module handles:
  - Data classes for Ash resources
  - Enum classes for Ash.Type.Atom with :one_of constraints
  - Sealed classes for Ash.Type.Union types
  - Embedded resource data classes
  """

  alias AshKotlinMultiplatform.Codegen.TypeMapper
  alias AshIntrospection.Helpers
  alias AshIntrospection.TypeSystem.Introspection

  @doc """
  Generates all schema types (data classes, enums, sealed classes) for the given resources.

  Returns a tuple of {data_classes, enum_classes, sealed_classes} as strings.
  """
  def generate_all_schemas(resources) do
    # Collect all types that need generation
    {enums, unions, embedded} = collect_types(resources)

    data_classes =
      resources
      |> Enum.map(&generate_data_class/1)
      |> Enum.join("\n\n")

    embedded_classes =
      embedded
      |> Enum.map(&generate_embedded_class/1)
      |> Enum.join("\n\n")

    enum_classes =
      enums
      |> Enum.uniq_by(fn {name, _} -> name end)
      |> Enum.map(&generate_enum_class/1)
      |> Enum.join("\n\n")

    sealed_classes =
      unions
      |> Enum.uniq_by(fn {name, _} -> name end)
      |> Enum.map(&generate_sealed_class/1)
      |> Enum.join("\n\n")

    {data_classes, embedded_classes, enum_classes, sealed_classes}
  end

  defp collect_types(resources) do
    resources
    |> Enum.reduce({[], [], MapSet.new()}, fn resource, {enums, unions, embedded} ->
      attributes = Ash.Resource.Info.public_attributes(resource)
      relationships = get_public_relationships(resource)

      # Collect types from attributes
      {new_enums, new_unions, new_embedded} =
        Enum.reduce(attributes, {enums, unions, embedded}, fn attr, {e, u, emb} ->
          collect_types_from_attribute(attr, e, u, emb)
        end)

      # Collect embedded resources from relationships (for embedded resources only)
      new_embedded =
        Enum.reduce(relationships, new_embedded, fn rel, emb ->
          if Introspection.is_embedded_resource?(rel.destination) do
            MapSet.put(emb, rel.destination)
          else
            emb
          end
        end)

      {new_enums, new_unions, new_embedded}
    end)
    |> then(fn {enums, unions, embedded} -> {enums, unions, MapSet.to_list(embedded)} end)
  end

  defp collect_types_from_attribute(attr, enums, unions, embedded) do
    type = attr.type
    constraints = attr.constraints || []

    {enums, unions, embedded} =
      case type do
        Ash.Type.Atom ->
          case Keyword.get(constraints, :one_of) do
            nil -> {enums, unions, embedded}
            values ->
              enum_name = generate_enum_name(attr.name)
              {[{enum_name, values} | enums], unions, embedded}
          end

        Ash.Type.Union ->
          union_types = Introspection.get_union_types_from_constraints(type, constraints)
          union_name = generate_union_name(attr.name)
          {enums, [{union_name, union_types} | unions], embedded}

        {:array, inner_type} ->
          if Introspection.is_embedded_resource?(inner_type) do
            {enums, unions, MapSet.put(embedded, inner_type)}
          else
            {enums, unions, embedded}
          end

        _ ->
          if Introspection.is_embedded_resource?(type) do
            {enums, unions, MapSet.put(embedded, type)}
          else
            {enums, unions, embedded}
          end
      end

    {enums, unions, embedded}
  end

  @doc """
  Generates a Kotlin data class for an Ash resource including relationships.
  """
  def generate_data_class(resource) do
    type_name = get_kotlin_type_name(resource)
    attributes = Ash.Resource.Info.public_attributes(resource)
    relationships = get_public_relationships(resource)

    attribute_fields =
      attributes
      |> Enum.map(&generate_field/1)

    relationship_fields =
      relationships
      |> Enum.map(fn rel -> generate_relationship_field(resource, rel) end)

    all_fields =
      (attribute_fields ++ relationship_fields)
      |> Enum.join(",\n    ")

    """
    @Serializable
    data class #{type_name}(
        #{all_fields}
    )
    """
  end

  defp get_public_relationships(resource) do
    try do
      Ash.Resource.Info.public_relationships(resource)
    rescue
      _ -> []
    end
  end

  @doc """
  Generates a Kotlin data class for an embedded Ash resource.
  """
  def generate_embedded_class(resource) do
    generate_data_class(resource)
  end

  defp generate_field(attribute) do
    kotlin_type = TypeMapper.get_kotlin_type(attribute)
    field_name = format_field_name(attribute.name)
    original_name = Atom.to_string(attribute.name)

    # Handle SerialName annotation if names differ
    serial_name =
      if original_name != field_name do
        "@SerialName(\"#{original_name}\")\n    "
      else
        ""
      end

    # Handle default values for nullable fields
    default =
      if attribute.allow_nil? do
        " = null"
      else
        ""
      end

    "#{serial_name}val #{field_name}: #{kotlin_type}#{default}"
  end

  defp generate_relationship_field(_resource, rel) do
    field_name = format_field_name(rel.name)
    original_name = Atom.to_string(rel.name)
    related_type_name = get_kotlin_type_name(rel.destination)

    # Handle SerialName annotation if names differ
    serial_name =
      if original_name != field_name do
        "@SerialName(\"#{original_name}\")\n    "
      else
        ""
      end

    # Determine the Kotlin type based on relationship type
    # Relationships are always nullable since they may not be loaded
    kotlin_type =
      case rel.type do
        :has_many ->
          "List<#{related_type_name}>?"

        :many_to_many ->
          "List<#{related_type_name}>?"

        :belongs_to ->
          "#{related_type_name}?"

        :has_one ->
          "#{related_type_name}?"

        _ ->
          "#{related_type_name}?"
      end

    "#{serial_name}val #{field_name}: #{kotlin_type} = null"
  end

  @doc """
  Generates a Kotlin enum class from Ash.Type.Atom with :one_of constraint.
  """
  def generate_enum_class({enum_name, values}) do
    entries =
      values
      |> Enum.map(fn value ->
        kotlin_name = value |> Atom.to_string() |> String.upcase() |> String.replace("-", "_")
        serial_name = Atom.to_string(value)
        "    @SerialName(\"#{serial_name}\") #{kotlin_name}"
      end)
      |> Enum.join(",\n")

    """
    @Serializable
    enum class #{enum_name} {
    #{entries}
    }
    """
  end

  @doc """
  Generates a Kotlin sealed class from Ash.Type.Union.
  """
  def generate_sealed_class({sealed_name, union_types}) do
    subclasses =
      union_types
      |> Enum.map(fn {type_name, type_config} ->
        generate_union_subclass(sealed_name, type_name, type_config)
      end)
      |> Enum.join("\n\n")

    """
    @Serializable
    sealed class #{sealed_name} {
    #{subclasses}
    }
    """
  end

  defp generate_union_subclass(parent_name, type_name, type_config) do
    class_name = type_name |> Atom.to_string() |> Helpers.snake_to_pascal_case()
    serial_name = Atom.to_string(type_name)

    member_type = Keyword.get(type_config, :type)
    member_constraints = Keyword.get(type_config, :constraints, [])

    # Generate fields based on the union member type
    fields =
      case member_type do
        Ash.Type.Map ->
          case Keyword.get(member_constraints, :fields) do
            nil -> "val value: Map<String, Any?>"
            field_specs -> generate_union_fields(field_specs)
          end

        Ash.Type.Struct ->
          case Keyword.get(member_constraints, :instance_of) do
            nil -> "val value: Map<String, Any?>"
            module -> "val value: #{TypeMapper.get_kotlin_class_name(module)}"
          end

        _ ->
          kotlin_type = TypeMapper.get_kotlin_type_for_type(member_type, member_constraints)
          "val value: #{kotlin_type}"
      end

    """
        @Serializable
        @SerialName("#{serial_name}")
        data class #{class_name}(
            #{fields}
        ) : #{parent_name}()
    """
  end

  defp generate_union_fields(field_specs) do
    field_specs
    |> Enum.map(fn {field_name, field_config} ->
      field_type = Keyword.get(field_config, :type, Ash.Type.String)
      field_constraints = Keyword.get(field_config, :constraints, [])
      allow_nil = Keyword.get(field_config, :allow_nil?, true)

      kotlin_type = TypeMapper.get_kotlin_type_for_type(field_type, field_constraints)
      kotlin_type = if allow_nil, do: "#{kotlin_type}?", else: kotlin_type

      formatted_name = format_field_name(field_name)
      original_name = Atom.to_string(field_name)

      serial_name =
        if original_name != formatted_name do
          "@SerialName(\"#{original_name}\") "
        else
          ""
        end

      default = if allow_nil, do: " = null", else: ""

      "#{serial_name}val #{formatted_name}: #{kotlin_type}#{default}"
    end)
    |> Enum.join(",\n            ")
  end

  defp generate_enum_name(attr_name) do
    attr_name
    |> Atom.to_string()
    |> Helpers.snake_to_pascal_case()
  end

  defp generate_union_name(attr_name) do
    name =
      attr_name
      |> Atom.to_string()
      |> Helpers.snake_to_pascal_case()

    "#{name}Union"
  end

  defp get_kotlin_type_name(resource) do
    case AshKotlinMultiplatform.Resource.Info.kotlin_type_name(resource) do
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

  defp format_field_name(name) do
    name
    |> Atom.to_string()
    |> Helpers.snake_to_camel_case()
  end
end
