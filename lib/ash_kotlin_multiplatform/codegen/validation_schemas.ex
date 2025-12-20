# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.ValidationSchemas do
  @moduledoc """
  Generates Kotlin validation annotations from Ash constraints.

  This module translates Ash attribute constraints into kotlinx.validation or
  javax.validation annotations that can be applied to generated Kotlin data classes.

  ## Supported Constraints

  - `allow_nil?: false` → `@field:NotNull`
  - `max_length: n` → `@field:Size(max = n)`
  - `min_length: n` → `@field:Size(min = n)`
  - `match: regex` → `@field:Pattern(regexp = "...")`
  - `min: n` → `@field:Min(n)`
  - `max: n` → `@field:Max(n)`
  - `one_of: [...]` → Custom validation or enum

  ## Generated Output

  ```kotlin
  @Serializable
  data class CreateTodoInput(
      @field:NotBlank
      @field:Size(min = 1, max = 255)
      val title: String,

      @field:Size(max = 1000)
      val description: String? = null
  )
  ```
  """

  alias AshKotlinMultiplatform.Codegen.TypeMapper

  @doc """
  Generates validation annotations for an attribute.

  ## Parameters

    * `attribute` - The Ash attribute struct
    * `opts` - Options for annotation generation

  ## Returns

  A list of annotation strings to be placed before the field.
  """
  def generate_annotations(attribute, opts \\ []) do
    constraints = attribute.constraints || []
    allow_nil? = Map.get(attribute, :allow_nil?, true)
    type = attribute.type

    annotations = []

    # Required field check
    annotations =
      if not allow_nil? do
        annotations ++ [not_null_annotation(type, opts)]
      else
        annotations
      end

    # String constraints
    annotations =
      if is_string_type?(type) do
        annotations ++ string_annotations(constraints, opts)
      else
        annotations
      end

    # Numeric constraints
    annotations =
      if is_numeric_type?(type) do
        annotations ++ numeric_annotations(constraints, opts)
      else
        annotations
      end

    # List/array constraints
    annotations =
      if is_array_type?(type) do
        annotations ++ array_annotations(constraints, opts)
      else
        annotations
      end

    # Pattern constraints (for strings with match)
    annotations =
      if is_string_type?(type) and Keyword.has_key?(constraints, :match) do
        annotations ++ [pattern_annotation(constraints[:match], opts)]
      else
        annotations
      end

    annotations
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  @doc """
  Generates a validation data class for action inputs.

  ## Parameters

    * `action` - The Ash action struct
    * `resource` - The resource module
    * `opts` - Generation options

  ## Returns

  A map containing:
    * `:class_name` - The Kotlin class name
    * `:fields` - List of field definitions with annotations
    * `:imports` - Required import statements
  """
  def generate_input_validation_class(action, resource, opts \\ []) do
    class_name = generate_class_name(action, resource, opts)

    arguments =
      action.arguments
      |> Enum.filter(&Map.get(&1, :public?, true))

    fields =
      Enum.map(arguments, fn arg ->
        annotations = generate_annotations(arg, opts)
        kotlin_type = TypeMapper.get_kotlin_type_for_type(arg.type, arg.constraints || [])
        field_name = format_field_name(arg.name, opts)

        %{
          name: field_name,
          type: kotlin_type,
          annotations: annotations,
          nullable: Map.get(arg, :allow_nil?, true),
          default: get_default_value(arg)
        }
      end)

    imports = collect_imports(fields)

    %{
      class_name: class_name,
      fields: fields,
      imports: imports
    }
  end

  @doc """
  Generates Kotlin code for a validated input class.

  ## Parameters

    * `validation_class` - Map from `generate_input_validation_class/3`
    * `opts` - Code generation options

  ## Returns

  A string of Kotlin code.
  """
  def generate_kotlin_code(validation_class, opts \\ []) do
    indent = Keyword.get(opts, :indent, "    ")

    imports =
      validation_class.imports
      |> Enum.map(&"import #{&1}")
      |> Enum.join("\n")

    fields =
      validation_class.fields
      |> Enum.map(&field_to_kotlin(&1, indent))
      |> Enum.join(",\n")

    """
    #{imports}

    @Serializable
    data class #{validation_class.class_name}(
    #{fields}
    )
    """
    |> String.trim()
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp not_null_annotation(type, _opts) do
    if is_string_type?(type) do
      "@field:NotBlank"
    else
      "@field:NotNull"
    end
  end

  defp string_annotations(constraints, _opts) do
    annotations = []

    min_length = Keyword.get(constraints, :min_length)
    max_length = Keyword.get(constraints, :max_length)

    annotations =
      cond do
        min_length && max_length ->
          annotations ++ ["@field:Size(min = #{min_length}, max = #{max_length})"]

        min_length ->
          annotations ++ ["@field:Size(min = #{min_length})"]

        max_length ->
          annotations ++ ["@field:Size(max = #{max_length})"]

        true ->
          annotations
      end

    annotations
  end

  defp numeric_annotations(constraints, _opts) do
    annotations = []

    min = Keyword.get(constraints, :min)
    max = Keyword.get(constraints, :max)

    annotations =
      if min do
        annotations ++ ["@field:Min(#{min})"]
      else
        annotations
      end

    annotations =
      if max do
        annotations ++ ["@field:Max(#{max})"]
      else
        annotations
      end

    annotations
  end

  defp array_annotations(constraints, _opts) do
    annotations = []

    min_length = Keyword.get(constraints, :min_length)
    max_length = Keyword.get(constraints, :max_length)

    annotations =
      cond do
        min_length && max_length ->
          annotations ++ ["@field:Size(min = #{min_length}, max = #{max_length})"]

        min_length ->
          annotations ++ ["@field:Size(min = #{min_length})"]

        max_length ->
          annotations ++ ["@field:Size(max = #{max_length})"]

        true ->
          annotations
      end

    annotations
  end

  defp pattern_annotation(regex, _opts) when is_struct(regex, Regex) do
    pattern = Regex.source(regex)
    # Escape for Kotlin string
    escaped = String.replace(pattern, "\\", "\\\\")
    "@field:Pattern(regexp = \"#{escaped}\")"
  end

  defp pattern_annotation(_, _opts), do: nil

  defp is_string_type?(type) do
    type in [Ash.Type.String, :string, Ash.Type.CiString, :ci_string]
  end

  defp is_numeric_type?(type) do
    type in [
      Ash.Type.Integer,
      :integer,
      Ash.Type.Float,
      :float,
      Ash.Type.Decimal,
      :decimal
    ]
  end

  defp is_array_type?({:array, _}), do: true
  defp is_array_type?(_), do: false

  defp generate_class_name(action, resource, _opts) do
    resource_name =
      resource
      |> Module.split()
      |> List.last()

    action_name =
      action.name
      |> to_string()
      |> Macro.camelize()

    "#{action_name}#{resource_name}Input"
  end

  defp format_field_name(name, _opts) do
    name
    |> to_string()
    |> AshIntrospection.Helpers.snake_to_camel_case()
  end

  defp get_default_value(arg) do
    if Map.get(arg, :allow_nil?, true) do
      "null"
    else
      nil
    end
  end

  defp collect_imports(fields) do
    base_imports = [
      "kotlinx.serialization.Serializable"
    ]

    validation_imports =
      fields
      |> Enum.flat_map(& &1.annotations)
      |> Enum.flat_map(&annotation_imports/1)
      |> Enum.uniq()

    base_imports ++ validation_imports
  end

  defp annotation_imports(annotation) do
    cond do
      String.contains?(annotation, "@field:NotNull") ->
        ["javax.validation.constraints.NotNull"]

      String.contains?(annotation, "@field:NotBlank") ->
        ["javax.validation.constraints.NotBlank"]

      String.contains?(annotation, "@field:Size") ->
        ["javax.validation.constraints.Size"]

      String.contains?(annotation, "@field:Min") ->
        ["javax.validation.constraints.Min"]

      String.contains?(annotation, "@field:Max") ->
        ["javax.validation.constraints.Max"]

      String.contains?(annotation, "@field:Pattern") ->
        ["javax.validation.constraints.Pattern"]

      true ->
        []
    end
  end

  defp field_to_kotlin(field, indent) do
    annotations =
      if Enum.empty?(field.annotations) do
        ""
      else
        field.annotations
        |> Enum.map(&"#{indent}#{&1}")
        |> Enum.join("\n")
        |> Kernel.<>("\n")
      end

    type_suffix = if field.nullable, do: "?", else: ""
    default_suffix = if field.default, do: " = #{field.default}", else: ""

    "#{annotations}#{indent}val #{field.name}: #{field.type}#{type_suffix}#{default_suffix}"
  end
end
