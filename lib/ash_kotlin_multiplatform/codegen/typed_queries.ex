# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.TypedQueries do
  @moduledoc """
  Generates Kotlin typed query types and field constants.

  Typed queries provide compile-time type safety for server-side rendered data
  and allow the same field selections to be used for client-side refetching.

  ## Usage

  Define typed queries in your RPC configuration:

  ```elixir
  kotlin_rpc do
    resource Todo do
      typed_query :todo_list,
        action: :list,
        fields: [:id, :title, :status, user: [:id, :name]]
    end
  end
  ```

  ## Generated Output

  ```kotlin
  // Type for todoList
  @Serializable
  data class TodoListResult(
      val id: String,
      val title: String,
      val status: TodoStatus,
      val user: TodoListUserResult
  )

  @Serializable
  data class TodoListUserResult(
      val id: String,
      val name: String
  )

  // Field selection for todoList - use with RPC actions for refetching
  object TodoListFields {
      val fields = listOf("id", "title", "status", mapOf("user" to listOf("id", "name")))
  }
  ```
  """

  alias AshKotlinMultiplatform.Codegen.TypeMapper
  alias AshIntrospection.FieldFormatter

  @doc """
  Generates typed query types and constants for the given typed queries.

  Returns an empty string if no typed queries are defined.
  """
  def generate_typed_queries_section([], _all_resources), do: ""

  def generate_typed_queries_section(typed_queries, all_resources) do
    queries_by_resource =
      Enum.group_by(typed_queries, fn {resource, _action, _query} -> resource end)

    sections =
      Enum.map(queries_by_resource, fn {resource, queries} ->
        resource_name = get_resource_name(resource)

        query_types_and_consts =
          Enum.map(queries, fn {resource, action, typed_query} ->
            generate_typed_query_type_and_const(resource, action, typed_query, all_resources)
          end)

        """
        // #{resource_name} Typed Queries
        #{Enum.join(query_types_and_consts, "\n\n")}
        """
      end)

    """
    // ============================
    // Typed Queries
    // ============================
    // Use these types and field constants for server-side rendering and data fetching.
    // The field constants can be used with the corresponding RPC actions for client-side refetching.

    #{Enum.join(sections, "\n\n")}
    """
    |> String.trim()
  end

  @doc """
  Generates a single typed query type and field constant object.
  """
  def generate_typed_query_type_and_const(resource, action, typed_query, _all_resources) do
    type_name = get_type_name(typed_query)
    fields_object_name = get_fields_object_name(typed_query)

    # Generate the data class for the result
    data_class = generate_result_data_class(resource, typed_query.fields, type_name)

    # Generate nested data classes for relationships
    nested_classes = generate_nested_data_classes(resource, typed_query.fields, type_name)

    # Determine if result is an array
    is_array = action.type == :read && !Map.get(action, :get?, false)

    # Generate the fields constant object
    fields_object = generate_fields_object(resource, typed_query.fields, fields_object_name)

    # Generate result type alias
    result_type =
      if is_array do
        "typealias #{type_name}List = List<#{type_name}>"
      else
        ""
      end

    [
      "// Type for #{typed_query.name}",
      data_class,
      nested_classes,
      result_type,
      "",
      "// Field selection for #{typed_query.name} - use with RPC actions for refetching",
      fields_object
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @doc """
  Generates typed queries from RPC configuration.
  """
  def generate_from_config(otp_app) do
    typed_queries = collect_typed_queries(otp_app)

    if Enum.empty?(typed_queries) do
      ""
    else
      all_resources = collect_all_resources(otp_app)
      generate_typed_queries_section(typed_queries, all_resources)
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp get_type_name(typed_query) do
    case Map.get(typed_query, :kotlin_result_type_name) do
      nil ->
        typed_query.name
        |> Atom.to_string()
        |> AshIntrospection.Helpers.snake_to_pascal_case()
        |> Kernel.<>("Result")

      name ->
        to_string(name)
    end
  end

  defp get_fields_object_name(typed_query) do
    case Map.get(typed_query, :kotlin_fields_object_name) do
      nil ->
        typed_query.name
        |> Atom.to_string()
        |> AshIntrospection.Helpers.snake_to_pascal_case()
        |> Kernel.<>("Fields")

      name ->
        to_string(name)
    end
  end

  defp generate_result_data_class(resource, fields, type_name) do
    field_defs = generate_field_definitions(resource, fields, type_name)

    """
    @Serializable
    data class #{type_name}(
    #{field_defs}
    )
    """
    |> String.trim()
  end

  defp generate_field_definitions(resource, fields, parent_type_name) do
    fields
    |> Enum.map(&generate_field_definition(&1, resource, parent_type_name))
    |> Enum.map(&"    #{&1}")
    |> Enum.join(",\n")
  end

  defp generate_field_definition(field, resource, parent_type_name) when is_atom(field) do
    attr = get_attribute_or_calculation(resource, field)

    if attr do
      kotlin_type = TypeMapper.get_kotlin_type(attr)
      formatted_name = format_field_for_client(field, resource)

      if formatted_name != to_string(field) do
        "@SerialName(\"#{formatted_name}\") val #{atom_to_camel_case(field)}: #{kotlin_type}"
      else
        "val #{formatted_name}: #{kotlin_type}"
      end
    else
      # Could be a relationship
      rel = Ash.Resource.Info.relationship(resource, field)

      if rel do
        nested_type_name = "#{parent_type_name}#{AshIntrospection.Helpers.snake_to_pascal_case(field)}Result"
        formatted_name = format_field_for_client(field, resource)

        if rel.cardinality == :many do
          "val #{formatted_name}: List<#{nested_type_name}>"
        else
          "val #{formatted_name}: #{nested_type_name}?"
        end
      else
        "val #{format_field_for_client(field, resource)}: Any?"
      end
    end
  end

  defp generate_field_definition({field, nested_fields}, resource, parent_type_name)
       when is_atom(field) and is_list(nested_fields) do
    rel = Ash.Resource.Info.relationship(resource, field)

    if rel do
      nested_type_name = "#{parent_type_name}#{AshIntrospection.Helpers.snake_to_pascal_case(field)}Result"
      formatted_name = format_field_for_client(field, resource)

      if rel.cardinality == :many do
        "val #{formatted_name}: List<#{nested_type_name}>"
      else
        "val #{formatted_name}: #{nested_type_name}?"
      end
    else
      "val #{format_field_for_client(field, resource)}: Any?"
    end
  end

  defp generate_field_definition({field, config}, resource, parent_type_name)
       when is_atom(field) and is_map(config) do
    # Handle {field, %{args: ..., fields: ...}} format
    nested_fields = Map.get(config, :fields, [])
    generate_field_definition({field, nested_fields}, resource, parent_type_name)
  end

  defp generate_field_definition(_field, _resource, _parent_type_name), do: ""

  defp generate_nested_data_classes(resource, fields, parent_type_name) do
    fields
    |> Enum.flat_map(&extract_nested_field_specs(&1, resource, parent_type_name))
    |> Enum.map(fn {nested_resource, nested_fields, nested_type_name} ->
      generate_result_data_class(nested_resource, nested_fields, nested_type_name) <>
        "\n" <>
        generate_nested_data_classes(nested_resource, nested_fields, nested_type_name)
    end)
    |> Enum.join("\n\n")
  end

  defp extract_nested_field_specs(field, _resource, _parent_type_name) when is_atom(field) do
    # Simple field - no nested specs
    []
  end

  defp extract_nested_field_specs({field, nested_fields}, resource, parent_type_name)
       when is_atom(field) and is_list(nested_fields) do
    rel = Ash.Resource.Info.relationship(resource, field)

    if rel do
      nested_type_name = "#{parent_type_name}#{AshIntrospection.Helpers.snake_to_pascal_case(field)}Result"
      [{rel.destination, nested_fields, nested_type_name}]
    else
      []
    end
  end

  defp extract_nested_field_specs({field, config}, resource, parent_type_name)
       when is_atom(field) and is_map(config) do
    nested_fields = Map.get(config, :fields, [])
    extract_nested_field_specs({field, nested_fields}, resource, parent_type_name)
  end

  defp extract_nested_field_specs(_field, _resource, _parent_type_name), do: []

  defp generate_fields_object(resource, fields, object_name) do
    formatted_fields = format_fields_for_kotlin(fields, resource)

    """
    object #{object_name} {
        val fields = #{formatted_fields}
    }
    """
    |> String.trim()
  end

  defp format_fields_for_kotlin(fields, resource) do
    items =
      fields
      |> Enum.map(&format_field_item(&1, resource))
      |> Enum.join(", ")

    "listOf(#{items})"
  end

  defp format_field_item(field, resource) when is_atom(field) do
    "\"#{format_field_for_client(field, resource)}\""
  end

  defp format_field_item({field, nested_fields}, resource)
       when is_atom(field) and is_list(nested_fields) do
    rel = Ash.Resource.Info.relationship(resource, field)
    nested_resource = if rel, do: rel.destination, else: nil
    nested = format_fields_for_kotlin(nested_fields, nested_resource)
    "mapOf(\"#{format_field_for_client(field, resource)}\" to #{nested})"
  end

  defp format_field_item({field, config}, resource) when is_atom(field) and is_map(config) do
    nested_fields = Map.get(config, :fields, [])
    args = Map.get(config, :args, %{})

    rel = Ash.Resource.Info.relationship(resource, field)
    nested_resource = if rel, do: rel.destination, else: nil
    nested = format_fields_for_kotlin(nested_fields, nested_resource)

    if Enum.empty?(args) do
      "mapOf(\"#{format_field_for_client(field, resource)}\" to #{nested})"
    else
      args_json = format_args_for_kotlin(args, resource)
      "mapOf(\"#{format_field_for_client(field, resource)}\" to mapOf(\"args\" to #{args_json}, \"fields\" to #{nested}))"
    end
  end

  defp format_field_item(field, _resource), do: inspect(field)

  defp format_args_for_kotlin(args, resource) do
    items =
      args
      |> Enum.map(fn {k, v} ->
        "\"#{format_field_for_client(k, resource)}\" to #{encode_kotlin_value(v)}"
      end)
      |> Enum.join(", ")

    "mapOf(#{items})"
  end

  defp encode_kotlin_value(v) when is_binary(v), do: "\"#{v}\""
  defp encode_kotlin_value(v) when is_number(v), do: to_string(v)
  defp encode_kotlin_value(v) when is_boolean(v), do: to_string(v)
  defp encode_kotlin_value(nil), do: "null"
  defp encode_kotlin_value(v) when is_list(v), do: "listOf(#{Enum.map_join(v, ", ", &encode_kotlin_value/1)})"

  defp encode_kotlin_value(v) when is_map(v) do
    items =
      v
      |> Enum.map(fn {k, val} -> "\"#{k}\" to #{encode_kotlin_value(val)}" end)
      |> Enum.join(", ")

    "mapOf(#{items})"
  end

  defp encode_kotlin_value(v), do: inspect(v)

  defp collect_typed_queries(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      # Get typed queries from RPC config if they exist
      domain
      |> AshKotlinMultiplatform.Rpc.Info.kotlin_rpc()
      |> Enum.flat_map(fn config ->
        typed_queries = Map.get(config, :typed_queries, [])

        Enum.map(typed_queries, fn query ->
          action = Ash.Resource.Info.action(config.resource, query.action)
          {config.resource, action, query}
        end)
      end)
    end)
  end

  defp collect_all_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
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

  defp get_attribute_or_calculation(resource, field) do
    Ash.Resource.Info.attribute(resource, field) ||
      Ash.Resource.Info.calculation(resource, field)
  end

  defp format_field_for_client(field_name, resource) do
    formatter = AshKotlinMultiplatform.Rpc.output_field_formatter()

    if resource do
      case get_kotlin_field_name(resource, field_name) do
        nil -> FieldFormatter.format_field_name(field_name, formatter)
        client_name -> to_string(client_name)
      end
    else
      FieldFormatter.format_field_name(field_name, formatter)
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

  defp atom_to_camel_case(atom) do
    atom
    |> Atom.to_string()
    |> AshIntrospection.Helpers.snake_to_camel_case()
  end
end
