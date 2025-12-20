# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.FilterTypes do
  @moduledoc """
  Generates Kotlin filter types for Ash resources.

  This module generates kotlinx.serialization data classes that represent
  the filter input types for Ash resources, enabling type-safe filtering
  from Kotlin clients.

  ## Supported Filter Operations

  - String types: `eq`, `notEq`, `in`
  - Numeric types: `eq`, `notEq`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, `in`
  - Date/time types: Same as numeric
  - Boolean types: `eq`, `notEq`
  - Enum/atom types: `eq`, `notEq`, `in`

  ## Generated Output

  ```kotlin
  @Serializable
  data class TodoFilterInput(
      val and: List<TodoFilterInput>? = null,
      val or: List<TodoFilterInput>? = null,
      val not: List<TodoFilterInput>? = null,
      val id: UuidFilter? = null,
      val title: StringFilter? = null,
      val status: EnumFilter<TodoStatus>? = null
  )

  @Serializable
  data class StringFilter(
      val eq: String? = null,
      val notEq: String? = null,
      @SerialName("in")
      val inValues: List<String>? = null
  )
  ```
  """

  alias AshIntrospection.FieldFormatter

  @doc """
  Generates filter types for multiple resources.
  """
  def generate_filter_types(resources) when is_list(resources) do
    Enum.map(resources, &generate_filter_type/1)
  end

  @doc """
  Generates filter types for resources, limited to allowed resources for relationships.
  """
  def generate_filter_types(resources, allowed_resources) when is_list(resources) do
    Enum.map(resources, &generate_filter_type(&1, allowed_resources))
  end

  @doc """
  Generates a filter type for a single resource.
  """
  def generate_filter_type(resource) do
    resource_name = get_resource_name(resource)
    filter_type_name = "#{resource_name}FilterInput"

    logical_operators = generate_logical_operators(filter_type_name)
    attribute_filters = generate_attribute_filters(resource)
    relationship_filters = generate_relationship_filters(resource)
    aggregate_filters = generate_aggregate_filters(resource)

    all_fields =
      (logical_operators ++ attribute_filters ++ aggregate_filters ++ relationship_filters)
      |> Enum.filter(&(&1 != ""))

    fields_str =
      all_fields
      |> Enum.map(&"    #{&1}")
      |> Enum.join(",\n")

    """
    @Serializable
    data class #{filter_type_name}(
    #{fields_str}
    )
    """
    |> String.trim()
  end

  @doc """
  Generates a filter type for a resource with relationship filtering limited to allowed resources.
  """
  def generate_filter_type(resource, allowed_resources) do
    resource_name = get_resource_name(resource)
    filter_type_name = "#{resource_name}FilterInput"

    logical_operators = generate_logical_operators(filter_type_name)
    attribute_filters = generate_attribute_filters(resource)
    relationship_filters = generate_relationship_filters(resource, allowed_resources)
    aggregate_filters = generate_aggregate_filters(resource)

    all_fields =
      (logical_operators ++ attribute_filters ++ aggregate_filters ++ relationship_filters)
      |> Enum.filter(&(&1 != ""))

    fields_str =
      all_fields
      |> Enum.map(&"    #{&1}")
      |> Enum.join(",\n")

    """
    @Serializable
    data class #{filter_type_name}(
    #{fields_str}
    )
    """
    |> String.trim()
  end

  @doc """
  Generates the base filter types (StringFilter, IntFilter, etc.).

  These are the primitive filter types used by resource filters.
  """
  def generate_base_filter_types do
    """
    @Serializable
    data class StringFilter(
        val eq: String? = null,
        val notEq: String? = null,
        @SerialName("in")
        val inValues: List<String>? = null
    )

    @Serializable
    data class IntFilter(
        val eq: Int? = null,
        val notEq: Int? = null,
        val greaterThan: Int? = null,
        val greaterThanOrEqual: Int? = null,
        val lessThan: Int? = null,
        val lessThanOrEqual: Int? = null,
        @SerialName("in")
        val inValues: List<Int>? = null
    )

    @Serializable
    data class DoubleFilter(
        val eq: Double? = null,
        val notEq: Double? = null,
        val greaterThan: Double? = null,
        val greaterThanOrEqual: Double? = null,
        val lessThan: Double? = null,
        val lessThanOrEqual: Double? = null,
        @SerialName("in")
        val inValues: List<Double>? = null
    )

    @Serializable
    data class BooleanFilter(
        val eq: Boolean? = null,
        val notEq: Boolean? = null
    )

    @Serializable
    data class UuidFilter(
        val eq: String? = null,
        val notEq: String? = null,
        @SerialName("in")
        val inValues: List<String>? = null
    )

    @Serializable
    data class DateFilter(
        val eq: kotlinx.datetime.LocalDate? = null,
        val notEq: kotlinx.datetime.LocalDate? = null,
        val greaterThan: kotlinx.datetime.LocalDate? = null,
        val greaterThanOrEqual: kotlinx.datetime.LocalDate? = null,
        val lessThan: kotlinx.datetime.LocalDate? = null,
        val lessThanOrEqual: kotlinx.datetime.LocalDate? = null,
        @SerialName("in")
        val inValues: List<kotlinx.datetime.LocalDate>? = null
    )

    @Serializable
    data class InstantFilter(
        val eq: kotlinx.datetime.Instant? = null,
        val notEq: kotlinx.datetime.Instant? = null,
        val greaterThan: kotlinx.datetime.Instant? = null,
        val greaterThanOrEqual: kotlinx.datetime.Instant? = null,
        val lessThan: kotlinx.datetime.Instant? = null,
        val lessThanOrEqual: kotlinx.datetime.Instant? = null,
        @SerialName("in")
        val inValues: List<kotlinx.datetime.Instant>? = null
    )

    @Serializable
    data class DecimalFilter(
        val eq: String? = null,
        val notEq: String? = null,
        val greaterThan: String? = null,
        val greaterThanOrEqual: String? = null,
        val lessThan: String? = null,
        val lessThanOrEqual: String? = null,
        @SerialName("in")
        val inValues: List<String>? = null
    )
    """
    |> String.trim()
  end

  @doc """
  Returns the imports needed for filter types.
  """
  def required_imports do
    [
      "kotlinx.serialization.Serializable",
      "kotlinx.serialization.SerialName"
    ]
  end

  @doc """
  Generates all filter types for resources in a domain.
  """
  def generate_all_filter_types(otp_app) do
    resources =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.uniq()

    base_types = generate_base_filter_types()
    resource_types = Enum.map_join(resources, "\n\n", &generate_filter_type/1)

    """
    #{base_types}

    #{resource_types}
    """
    |> String.trim()
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp generate_logical_operators(filter_type_name) do
    [
      "val and: List<#{filter_type_name}>? = null",
      "val or: List<#{filter_type_name}>? = null",
      "val not: List<#{filter_type_name}>? = null"
    ]
  end

  defp generate_attribute_filters(resource) do
    attrs =
      resource
      |> Ash.Resource.Info.public_attributes()

    calcs =
      resource
      |> Ash.Resource.Info.public_calculations()

    (attrs ++ calcs)
    |> Enum.map(&generate_attribute_filter(&1, resource))
    |> Enum.filter(&(&1 != ""))
  end

  defp generate_attribute_filter(attribute, resource) do
    filter_type = get_filter_type_for_attribute(attribute)
    formatted_name = format_field_for_client(attribute.name, resource)

    "val #{formatted_name}: #{filter_type}? = null"
  end

  defp generate_aggregate_filters(resource) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Enum.filter(&(&1.kind in [:sum, :count]))
    |> Enum.map(&generate_aggregate_filter(&1, resource))
    |> Enum.filter(&(&1 != ""))
  end

  defp generate_aggregate_filter(%{kind: :count, name: name}, resource) do
    formatted_name = format_field_for_client(name, resource)
    "val #{formatted_name}: IntFilter? = null"
  end

  defp generate_aggregate_filter(%{kind: :sum} = aggregate, resource) do
    related_resource =
      Enum.reduce(aggregate.relationship_path, resource, fn
        next, acc -> Ash.Resource.Info.relationship(acc, next).destination
      end)

    field =
      Ash.Resource.Info.attribute(related_resource, aggregate.field) ||
        Ash.Resource.Info.calculation(related_resource, aggregate.field)

    if field do
      filter_type = get_filter_type_for_attribute(field)
      formatted_name = format_field_for_client(aggregate.name, resource)
      "val #{formatted_name}: #{filter_type}? = null"
    else
      ""
    end
  end

  defp generate_relationship_filters(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.map(&generate_relationship_filter/1)
  end

  defp generate_relationship_filters(resource, allowed_resources) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(fn rel ->
      Enum.member?(allowed_resources, rel.destination)
    end)
    |> Enum.map(&generate_relationship_filter/1)
  end

  defp generate_relationship_filter(relationship) do
    related_resource = relationship.destination
    related_resource_name = get_resource_name(related_resource)
    filter_type_name = "#{related_resource_name}FilterInput"

    formatted_name = format_field(relationship.name)
    "val #{formatted_name}: #{filter_type_name}? = null"
  end

  defp get_filter_type_for_attribute(attribute) do
    type = attribute.type

    cond do
      type in [Ash.Type.String, Ash.Type.CiString, :string] ->
        "StringFilter"

      type in [Ash.Type.Integer, :integer] ->
        "IntFilter"

      type in [Ash.Type.Float, :float] ->
        "DoubleFilter"

      type in [Ash.Type.Decimal, :decimal] ->
        "DecimalFilter"

      type in [Ash.Type.Boolean, :boolean] ->
        "BooleanFilter"

      type in [Ash.Type.UUID, :uuid] ->
        "UuidFilter"

      type in [Ash.Type.Date, :date] ->
        "DateFilter"

      type in [
        Ash.Type.UtcDatetime,
        Ash.Type.UtcDatetimeUsec,
        Ash.Type.DateTime,
        Ash.Type.NaiveDatetime,
        :datetime,
        :utc_datetime,
        :naive_datetime
      ] ->
        "InstantFilter"

      type == Ash.Type.Atom ->
        "StringFilter"

      true ->
        # Default to string filter for unknown types
        "StringFilter"
    end
  end

  defp get_resource_name(resource) do
    case AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_type_name(resource) do
      nil ->
        resource
        |> Module.split()
        |> List.last()

      name ->
        to_string(name)
    end
  rescue
    _ ->
      resource
      |> Module.split()
      |> List.last()
  end

  defp format_field(field_name) do
    field_name
    |> to_string()
    |> AshIntrospection.Helpers.snake_to_camel_case()
  end

  defp format_field_for_client(field_name, resource) do
    formatter = AshKotlinMultiplatform.Rpc.output_field_formatter()

    case get_kotlin_field_name(resource, field_name) do
      nil -> FieldFormatter.format_field_name(field_name, formatter)
      client_name -> to_string(client_name)
    end
  end

  defp get_kotlin_field_name(resource, field_name) do
    case AshKotlinMultiplatform.Resource.Info.kotlin_field_names(resource) do
      field_names when is_list(field_names) ->
        Keyword.get(field_names, field_name)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
