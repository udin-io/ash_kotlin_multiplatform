# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.TypeMapper do
  @moduledoc """
  Maps Ash types to Kotlin types.

  This module is responsible for converting Ash type definitions to their
  Kotlin equivalents, handling:
  - Primitive types (String, Int, Boolean, etc.)
  - Date/time types (using kotlinx-datetime or java.time)
  - Collection types (List<T>)
  - Nullable types (T?)
  - Custom type overrides
  """

  alias AshIntrospection.TypeSystem.Introspection

  # Kotlin types with no serializer the compiler can resolve on its own.
  @contextual_types ["kotlinx.datetime.Instant", "Any"]

  # Every java.time type `map_type/2` can emit. kotlinx-serialization ships a
  # serializer for none of them, so all of them need the annotation and the
  # matching entry in the `SerializersModule`
  # `AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic.generate_shared_json/0`
  # builds. Longer names are not shadowed by shorter prefixes: the trailing `\b`
  # in the pattern below rejects `java.time.LocalDate` inside
  # `java.time.LocalDateTime`.
  @java_time_contextual_types [
    "java.time.LocalDate",
    "java.time.LocalTime",
    "java.time.Instant",
    "java.time.ZonedDateTime",
    "java.time.LocalDateTime"
  ]

  @doc """
  Returns every java.time type the mapper can emit.

  `AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic` declares one `KSerializer` per
  entry, so the list is the single source of truth for which types get annotated
  and which get a serializer. The two must not drift.
  """
  def java_time_contextual_types, do: @java_time_contextual_types

  @doc """
  Returns the Kotlin type for an Ash attribute.

  ## Parameters
  - `attribute` - An Ash attribute struct
  - `opts` - Options including :nullable (default: based on allow_nil?)

  ## Returns
  A string representing the Kotlin type.
  """
  def get_kotlin_type(attribute, opts \\ []) do
    nullable = Keyword.get(opts, :nullable, attribute.allow_nil?)
    type = attribute.type
    constraints = attribute.constraints || []

    kotlin_type = do_get_kotlin_type(type, constraints)

    if nullable do
      "#{kotlin_type}?"
    else
      kotlin_type
    end
  end

  @doc """
  Returns the Kotlin type for an Ash type and constraints.

  ## Parameters
  - `type` - The Ash type module or tuple
  - `constraints` - The type constraints

  ## Returns
  A string representing the Kotlin type.
  """
  def get_kotlin_type_for_type(type, constraints \\ []) do
    do_get_kotlin_type(type, constraints)
  end

  @doc """
  Annotates the types that have no compile-time serializer with `@Contextual`.

  Three groups need it.

  `kotlinx.datetime.Instant`: kotlinx-datetime 0.6 shipped a default serializer for
  it; 0.7 deprecated the class in favour of `kotlin.time.Instant` and dropped both
  the default and the concrete `InstantIso8601Serializer` object. A generated file
  cannot know which version the consumer pinned, so it defers the lookup to the
  `SerializersModule` that
  `AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic.generate_shared_json/0`
  registers.

  `Any`: only ever from a consumer's own `:untyped_map_type` or
  `:type_mapping_overrides`. Since #51 the mapper emits `JsonElement` for every
  untyped shape, because kotlinx-serialization has no serializer for `Any` and
  never will: a bare `Any` inside a `@Serializable` class is a compile error, and
  `@Contextual Any` is a compile that throws `SerializationException: Serializer
  for class 'Any' is not found` the moment the field holds something. The
  annotation stays so a consumer who names `Any` still compiles; making it decode
  is then theirs to arrange.

  Annotates in type position rather than on the property, so element types resolve
  too: `List<@Contextual Instant>` consults the module for `Instant`, while
  `@Contextual val x: List<Instant>` would look for a serializer registered for
  `List<Instant>` and fail at runtime.

  The `java.time` types, under `datetime_library: :java_time` only:
  kotlinx-serialization has a serializer for none of them, so every date or time
  field was a SERIALIZER_NOT_FOUND compile error and the option could not produce a
  compiling client at all (#45). `KotlinStatic` registers an ISO-8601 serializer per
  type, which is what this annotation resolves against.

  Matches whole words only, so `Any` does not touch `AnyOf` or a resource named
  `Anything`. Idempotent, so it is safe to apply to an already-annotated type.
  """
  def annotate_contextual_types(kotlin_type) when is_binary(kotlin_type) do
    Enum.reduce(contextual_types(), kotlin_type, fn type, acc ->
      String.replace(acc, ~r/(?<!@Contextual )\b#{Regex.escape(type)}\b/, "@Contextual #{type}")
    end)
  end

  defp contextual_types do
    case AshKotlinMultiplatform.datetime_library() do
      :java_time -> @contextual_types ++ @java_time_contextual_types
      _kotlinx_datetime -> @contextual_types
    end
  end

  defp do_get_kotlin_type(type, constraints) do
    # Check for custom overrides first
    case find_override(type) do
      nil -> map_type(type, constraints)
      override -> override
    end
  end

  defp find_override(type) do
    overrides = AshKotlinMultiplatform.type_mapping_overrides()

    Enum.find_value(overrides, fn {ash_type, kotlin_type} ->
      if ash_type == type, do: kotlin_type
    end)
  end

  defp map_type({:array, inner_type}, constraints) do
    items_constraints = Keyword.get(constraints, :items, [])
    inner_kotlin_type = do_get_kotlin_type(inner_type, items_constraints)
    "List<#{inner_kotlin_type}>"
  end

  defp map_type(Ash.Type.String, _constraints), do: "String"
  defp map_type(Ash.Type.CiString, _constraints), do: "String"
  defp map_type(Ash.Type.Integer, _constraints), do: "Int"
  defp map_type(Ash.Type.Float, _constraints), do: "Double"
  defp map_type(Ash.Type.Boolean, _constraints), do: "Boolean"
  defp map_type(Ash.Type.Binary, _constraints), do: "ByteArray"

  # Decimal - use String for KMP compatibility
  defp map_type(Ash.Type.Decimal, _constraints), do: "String"

  # UUID types - use String for KMP compatibility
  defp map_type(Ash.Type.UUID, _constraints), do: "String"

  # A vector belongs on the wire as a JSON array of numbers, never as the packed
  # binary `%Ash.Vector{}` carries. `AshIntrospection.Rpc.ValueFormatter` expands
  # it with `Ash.Vector.to_list/1`
  # (`deps/ash_introspection/lib/ash_introspection/rpc/value_formatter.ex:206`),
  # but `Rpc.Runner` never calls that formatter, so a vector *response* still
  # raises `Jason.EncodeError` today — #71. This type already serves a request
  # payload, because `Ash.Type.Vector.cast_input/2` accepts a list, and it is
  # what the array decodes into once #71 lands.
  #
  # `Double` and not `Float`, because kotlinx-serialization reads a JSON number
  # into whichever the field declares and `Double` cannot lose a value the
  # encoder wrote (#30).
  defp map_type(Ash.Type.Vector, _constraints), do: "List<Double>"

  # Date/time types
  defp map_type(Ash.Type.Date, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.LocalDate"
      :java_time -> "java.time.LocalDate"
    end
  end

  defp map_type(Ash.Type.Time, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.LocalTime"
      :java_time -> "java.time.LocalTime"
    end
  end

  defp map_type(Ash.Type.UtcDatetime, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.Instant"
      :java_time -> "java.time.Instant"
    end
  end

  defp map_type(Ash.Type.UtcDatetimeUsec, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.Instant"
      :java_time -> "java.time.Instant"
    end
  end

  defp map_type(Ash.Type.DateTime, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.Instant"
      :java_time -> "java.time.ZonedDateTime"
    end
  end

  defp map_type(Ash.Type.NaiveDatetime, _constraints) do
    case AshKotlinMultiplatform.datetime_library() do
      :kotlinx_datetime -> "kotlinx.datetime.LocalDateTime"
      :java_time -> "java.time.LocalDateTime"
    end
  end

  # Atom type - check for :one_of constraint for enum
  defp map_type(Ash.Type.Atom, constraints) do
    case Keyword.get(constraints, :one_of) do
      nil -> "String"
      # For enums, we'll generate enum classes separately
      _values -> "String"
    end
  end

  # Map types
  defp map_type(Ash.Type.Map, constraints) do
    case Keyword.get(constraints, :fields) do
      nil -> AshKotlinMultiplatform.untyped_map_type()
      # For typed maps, we'll generate data classes separately
      _fields -> AshKotlinMultiplatform.untyped_map_type()
    end
  end

  defp map_type(Ash.Type.Keyword, _constraints) do
    AshKotlinMultiplatform.untyped_map_type()
  end

  # Tuple type. `JsonElement` rather than `Any` for the same reason the untyped
  # map takes it: a positional list of unknown types has no Kotlin element type,
  # and `Any` compiles but does not decode (#51).
  defp map_type(Ash.Type.Tuple, constraints) do
    case Keyword.get(constraints, :fields) do
      nil -> "List<JsonElement>"
      _fields -> "List<JsonElement>"
    end
  end

  # Union type. A resource attribute gets the sealed class generated for it by
  # `AshKotlinMultiplatform.Codegen.ResourceSchemas` — that lookup needs the
  # attribute name, which this function does not have. Everywhere else (union
  # member fields, action metadata, identity types) there is no such class, so the
  # union falls back to a contextual `Any`.
  defp map_type(Ash.Type.Union, _constraints) do
    "JsonElement"
  end

  # Struct type
  defp map_type(Ash.Type.Struct, constraints) do
    case Keyword.get(constraints, :instance_of) do
      nil -> AshKotlinMultiplatform.untyped_map_type()
      module -> get_kotlin_class_name(module)
    end
  end

  # Check if it's an embedded resource
  defp map_type(type, constraints) when is_atom(type) do
    cond do
      Introspection.is_embedded_resource?(type) ->
        get_kotlin_class_name(type)

      # Check for NewType
      Ash.Type.NewType.new_type?(type) ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(type, constraints, &has_interop_field_names?/1)

        do_get_kotlin_type(unwrapped_type, unwrapped_constraints)

      # An Ash type this module has no case for. `JsonElement` carries whatever
      # the server sent without claiming to know its shape; configure
      # :type_mapping_overrides to name a concrete Kotlin type.
      Introspection.is_ash_type?(type) ->
        "JsonElement"

      true ->
        # Module that might be a custom type
        "JsonElement"
    end
  end

  # Fallback for non-atom types
  defp map_type(_, _constraints), do: "JsonElement"

  @doc """
  Checks if a module has interop_field_names/0 callback.
  """
  def has_interop_field_names?(nil), do: false

  def has_interop_field_names?(module) when is_atom(module) do
    Code.ensure_loaded?(module) && function_exported?(module, :interop_field_names, 0)
  end

  def has_interop_field_names?(_), do: false

  @doc """
  Gets the interop_field_names as a map, or empty map if not available.
  """
  def get_interop_field_names_map(nil), do: %{}

  def get_interop_field_names_map(module) when is_atom(module) do
    if Code.ensure_loaded?(module) && function_exported?(module, :interop_field_names, 0) do
      module.interop_field_names() |> Map.new()
    else
      %{}
    end
  end

  def get_interop_field_names_map(_), do: %{}

  @doc """
  Generates a Kotlin class name from an Elixir module.

  ## Examples

      iex> get_kotlin_class_name(MyApp.Accounts.User)
      "User"
  """
  def get_kotlin_class_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
  end

  @doc """
  Checks if an Ash type should be generated as a Kotlin enum class.

  Requires `:one_of` to hold a list, not merely to be present.
  `AshKotlinMultiplatform.Codegen.ResourceSchemas.collect_types/1` generates no
  class for a nil `:one_of`, so a field must not name one for it either.
  """
  def is_enum_type?(type, constraints) do
    type == Ash.Type.Atom and is_list(Keyword.get(constraints, :one_of))
  end

  @doc """
  Returns the enum values for an Ash.Type.Atom with :one_of constraint.
  """
  def get_enum_values(constraints) do
    Keyword.get(constraints, :one_of, [])
  end

  @doc """
  Checks if an Ash type should be generated as a Kotlin sealed class (union).
  """
  def is_union_type?(type) do
    type == Ash.Type.Union
  end

  @doc """
  Returns the union member types from constraints.
  """
  def get_union_types(type, constraints) do
    Introspection.get_union_types_from_constraints(type, constraints)
  end
end
