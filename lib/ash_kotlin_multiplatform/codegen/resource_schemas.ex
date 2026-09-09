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

    # Exactly the resources this pass declares a data class for. Nothing else may
    # be named by a relationship field - see `generate_relationship_fields/2`.
    emitted = resources ++ embedded

    data_classes =
      resources
      |> Enum.map(&generate_data_class(&1, emitted))
      |> Enum.join("\n\n")

    embedded_classes =
      embedded
      |> Enum.map(&generate_embedded_class(&1, emitted))
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

    # Shares its predicates with `field_kotlin_type/1`: whatever gets a class here
    # is exactly what a field is allowed to name, so the two cannot drift into
    # orphaned classes or dangling references.
    cond do
      TypeMapper.is_enum_type?(type, constraints) ->
        enum_name = generate_enum_name(attr.name)
        {[{enum_name, TypeMapper.get_enum_values(constraints)} | enums], unions, embedded}

      TypeMapper.is_union_type?(type) ->
        union_types = Introspection.get_union_types_from_constraints(type, constraints)
        union_name = generate_union_name(attr.name)
        {enums, [{union_name, union_types} | unions], embedded}

      true ->
        {enums, unions, collect_embedded_resource(type, embedded)}
    end
  end

  defp collect_embedded_resource({:array, inner_type}, embedded) do
    collect_embedded_resource(inner_type, embedded)
  end

  defp collect_embedded_resource(type, embedded) do
    if Introspection.is_embedded_resource?(type) do
      MapSet.put(embedded, type)
    else
      embedded
    end
  end

  @doc """
  Generates a Kotlin data class for an Ash resource including relationships.

  `emitted_resources` is every resource the same generation pass declares a class
  for. A relationship whose destination is not in it is dropped rather than
  emitted against a type that does not exist; pass the full set, not just the
  resource being generated.
  """
  def generate_data_class(resource, emitted_resources) do
    type_name = get_kotlin_type_name(resource)
    attributes = Ash.Resource.Info.public_attributes(resource)

    attribute_fields =
      attributes
      |> Enum.map(&generate_field/1)

    relationship_fields = generate_relationship_fields(resource, emitted_resources)

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

  # A relationship field may only name a class this file declares. `Author` has a
  # public `has_many :secrets` to a resource the Kotlin DSL never published, and
  # emitting `List<Secret>` for it made every generated file fail to compile with
  # "Unresolved reference 'Secret'" (#44).
  #
  # Dropping the field is what the server already does. `AshKotlinMultiplatform.Rpc.Runner`
  # hands `FieldSelector` an `is_interop_resource?` gate, so a nested request into
  # `Author.secrets` comes back `unknown_field`. Generating the missing class instead
  # would publish a resource the DSL deliberately withheld.
  defp generate_relationship_fields(resource, emitted_resources) do
    emitted = MapSet.new(emitted_resources)

    resource
    |> get_public_relationships()
    |> Enum.filter(&MapSet.member?(emitted, &1.destination))
    |> Enum.map(&generate_relationship_field/1)
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
  def generate_embedded_class(resource, emitted_resources) do
    generate_data_class(resource, emitted_resources)
  end

  defp generate_field(attribute) do
    kotlin_type = field_kotlin_type(attribute)
    field_name = format_field_name(attribute.name)
    original_name = Atom.to_string(attribute.name)

    # Handle SerialName annotation based on output field formatter
    # If server outputs camelCase (default), Kotlin property names already match
    # If server outputs snake_case, we need @SerialName for the snake_case JSON key
    serial_name = get_serial_name_annotation(original_name, field_name)

    # All fields except `id` get defaults since RPC uses sparse fieldsets
    # This allows responses to omit fields that weren't requested
    {kotlin_type, default} =
      cond do
        # ID field is always required and present
        attribute.name == :id ->
          {kotlin_type, ""}

        # Nullable fields get null default
        attribute.allow_nil? ->
          {kotlin_type, " = null"}

        # Non-nullable fields need to be made nullable with defaults for sparse responses
        true ->
          nullable_type = make_nullable(kotlin_type)
          default_value = get_default_for_type(kotlin_type)
          {nullable_type, " = #{default_value}"}
      end

    "#{serial_name}val #{field_name}: #{TypeMapper.annotate_contextual_types(kotlin_type)}#{default}"
  end

  # A union attribute has a sealed class generated for it by `collect_types/1`, and
  # a `one_of` atom attribute an enum class; the field has to name that class or
  # the class is emitted and referenced by nothing. `TypeMapper` cannot supply the
  # name: it maps from the Ash type alone, while both names come from the attribute
  # name.
  #
  # Both `collect_types/1` and `generate_data_class/1` read
  # `Ash.Resource.Info.public_attributes/1` and share the predicates below, so the
  # class a field names always exists. Nothing else may take these branches — a
  # union or `one_of` atom reached through an action argument or a union member has
  # no generated class, and naming one there would emit a dangling reference.
  defp field_kotlin_type(attribute) do
    constraints = attribute.constraints || []

    cond do
      TypeMapper.is_union_type?(attribute.type) ->
        nullable_class_name(generate_union_name(attribute.name), attribute)

      TypeMapper.is_enum_type?(attribute.type, constraints) ->
        nullable_class_name(generate_enum_name(attribute.name), attribute)

      true ->
        TypeMapper.get_kotlin_type(attribute)
    end
  end

  defp nullable_class_name(class_name, %{allow_nil?: true}), do: "#{class_name}?"
  defp nullable_class_name(class_name, _attribute), do: class_name

  defp make_nullable(kotlin_type) do
    if String.ends_with?(kotlin_type, "?") do
      kotlin_type
    else
      "#{kotlin_type}?"
    end
  end

  defp get_default_for_type(_kotlin_type), do: "null"

  defp generate_relationship_field(rel) do
    field_name = format_field_name(rel.name)
    original_name = Atom.to_string(rel.name)
    related_type_name = get_kotlin_type_name(rel.destination)

    # Handle SerialName annotation based on output field formatter
    serial_name = get_serial_name_annotation(original_name, field_name)

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
            nil -> "val value: #{untyped_map_type()}"
            field_specs -> generate_union_fields(field_specs)
          end

        Ash.Type.Struct ->
          case Keyword.get(member_constraints, :instance_of) do
            nil -> "val value: #{untyped_map_type()}"
            module -> "val value: #{TypeMapper.get_kotlin_class_name(module)}"
          end

        _ ->
          kotlin_type =
            member_type
            |> TypeMapper.get_kotlin_type_for_type(member_constraints)
            |> TypeMapper.annotate_contextual_types()

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

      kotlin_type =
        field_type
        |> TypeMapper.get_kotlin_type_for_type(field_constraints)
        |> TypeMapper.annotate_contextual_types()

      kotlin_type = if allow_nil, do: "#{kotlin_type}?", else: kotlin_type

      formatted_name = format_field_name(field_name)
      original_name = Atom.to_string(field_name)

      # Use inline version of serial_name for union fields
      serial_name = get_inline_serial_name_annotation(original_name, formatted_name)

      default = if allow_nil, do: " = null", else: ""

      "#{serial_name}val #{formatted_name}: #{kotlin_type}#{default}"
    end)
    |> Enum.join(",\n            ")
  end

  defp untyped_map_type do
    AshKotlinMultiplatform.untyped_map_type()
    |> TypeMapper.annotate_contextual_types()
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

  defp format_field_name(name) do
    name
    |> Atom.to_string()
    |> Helpers.snake_to_camel_case()
  end

  # Determines the correct @SerialName annotation based on output_field_formatter config
  # When server outputs camelCase (default): no annotation needed, Kotlin properties already match
  # When server outputs snake_case: need @SerialName("snake_case") since Kotlin properties are camelCase
  defp get_serial_name_annotation(original_name, kotlin_field_name) do
    output_formatter = AshKotlinMultiplatform.output_field_formatter()

    case output_formatter do
      :snake_case ->
        # Server outputs snake_case, Kotlin properties are camelCase
        # Need @SerialName to map snake_case JSON to camelCase property
        if original_name != kotlin_field_name do
          "@SerialName(\"#{original_name}\")\n    "
        else
          ""
        end

      _camel_case ->
        # Server outputs camelCase (default), Kotlin properties are camelCase
        # No annotation needed - property names match JSON keys
        ""
    end
  end

  # Inline version for union fields (no newline)
  defp get_inline_serial_name_annotation(original_name, kotlin_field_name) do
    output_formatter = AshKotlinMultiplatform.output_field_formatter()

    case output_formatter do
      :snake_case ->
        if original_name != kotlin_field_name do
          "@SerialName(\"#{original_name}\") "
        else
          ""
        end

      _camel_case ->
        ""
    end
  end
end
