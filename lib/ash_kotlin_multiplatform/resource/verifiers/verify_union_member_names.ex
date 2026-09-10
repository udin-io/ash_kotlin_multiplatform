# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Resource.Verifiers.VerifyUnionMemberNames do
  @moduledoc """
  Rejects union member names that Kotlin cannot compile.

  A union attribute is the one place in this generator where a name written
  inside `constraints` becomes a Kotlin identifier.
  `AshKotlinMultiplatform.Codegen.ResourceSchemas.generate_sealed_class/1` turns
  each member name into a subclass name and each field of a map member into a
  property, so a member named `is_valid?` emitted `data class IsValid?(` and a
  member field named `ok?` emitted `val ok?:` — output the Kotlin compile gate
  refuses. Nothing caught it, because the resource verifiers only ever looked at
  top-level field names.

  Deliberately narrow. Every other constraint name this generator meets is
  erased before it reaches Kotlin: a `:map` attribute becomes an untyped map, a
  `:tuple` a `List`, a union outside a resource attribute a `@Contextual Any`.
  Their field names never appear in the output, so rejecting them would fail
  builds over names that cause no harm. Only what `ResourceSchemas` actually
  emits is checked here — a public attribute whose type is `Ash.Type.Union`,
  which is the sole shape `collect_types/1` generates a sealed class for.

  There is no escape hatch by design: `interop_field_names/0` and the
  `field_names` DSL option are not consulted when emitting a sealed class, so a
  mapping would not change the generated name. Rename the member.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    resource = dsl[:persist][:module]

    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.flat_map(&validate_attribute(resource, &1))
    |> case do
      [] -> :ok
      errors -> format_errors(resource, errors)
    end
  end

  defp validate_attribute(_resource, %{type: Ash.Type.Union} = attribute) do
    attribute.constraints
    |> Kernel.||([])
    |> Keyword.get(:types, [])
    |> Enum.flat_map(&validate_member(attribute.name, &1))
  end

  defp validate_attribute(_resource, _attribute), do: []

  defp validate_member(attribute_name, {member_name, member_config}) do
    name_errors =
      if invalid_name?(member_name) do
        [{attribute_name, :union_member, member_name, better_name(member_name)}]
      else
        []
      end

    name_errors ++ validate_member_fields(attribute_name, member_name, member_config)
  end

  # Only a member whose type is literally `Ash.Type.Map` with `fields` gets its
  # field names emitted; every other member type reaches Kotlin as a single
  # `value` property, so its constraint names are erased.
  defp validate_member_fields(attribute_name, member_name, member_config) do
    with Ash.Type.Map <- Keyword.get(member_config, :type),
         fields when is_list(fields) <-
           member_config |> Keyword.get(:constraints, []) |> Keyword.get(:fields) do
      fields
      |> Enum.filter(fn {field_name, _} -> invalid_name?(field_name) end)
      |> Enum.map(fn {field_name, _} ->
        {attribute_name, {:member_field, member_name}, field_name, better_name(field_name)}
      end)
    else
      _ -> []
    end
  end

  @doc false
  def invalid_name?(name), do: Regex.match?(~r/_+\d|\?/, to_string(name))

  @doc false
  def better_name(name) do
    name
    |> to_string()
    |> String.replace(~r/_+\d/, &String.trim_leading(&1, "_"))
    |> String.replace("?", "")
  end

  defp format_errors(resource, errors) do
    details =
      errors
      |> Enum.group_by(fn {attribute_name, _kind, _name, _suggested} -> attribute_name end)
      |> Enum.map_join("\n\n", &format_attribute_group/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid union member names on resource #{inspect(resource)}.

       These names become Kotlin identifiers in the sealed class generated for the
       attribute, and a question mark or an underscore before a digit is not valid there.

       #{details}

       Rename them on the resource. A `field_names` mapping does not help: the sealed
       class is generated from the constraint names directly.
       """
     )}
  end

  defp format_attribute_group({attribute_name, errors}) do
    lines =
      Enum.map_join(errors, "\n", fn
        {_attribute_name, :union_member, name, suggested} ->
          "  - union member #{name} → #{suggested}"

        {_attribute_name, {:member_field, member_name}, name, suggested} ->
          "  - field #{name} of union member #{member_name} → #{suggested}"
      end)

    "Attribute #{inspect(attribute_name)}:\n#{lines}"
  end
end
