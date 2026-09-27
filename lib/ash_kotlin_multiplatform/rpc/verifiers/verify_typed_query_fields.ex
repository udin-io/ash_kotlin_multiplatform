# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Verifiers.VerifyTypedQueryFields do
  @moduledoc """
  Fails `mix compile` when a `typed_query`'s `fields` name something that does
  not resolve to a public attribute, relationship or `field?: true`
  calculation on the resource — walking into nested relationship selections.

  Measured on `main` (`d70ce8b6`), the codegen this verifier now gates in
  front of accepted any attribute or calculation, public or not, and never
  filtered a `field?: false` calculation. That produced three distinct
  broken outputs:

    * a `field?: false` calculation got a typed, `@SerialName`-annotated
      Kotlin field that always decodes to `null` — the calculation's value
      never reaches the struct `AshIntrospection.Rpc.FieldExtractor` reads;
    * a private attribute or relationship got a real Kotlin field, and the
      server's field selector then refuses it at request time with
      `unknown_field`;
    * a name that is not a field at all fell to a catch-all `val x: Any?`,
      which fails this project's `@Serializable` convention and breaks the
      Kotlin compile gate rather than merely misleading a client.

  `AshKotlinMultiplatform.Resource.Info.resolve_typed_query_field/2` is the
  single source of truth this verifier and `AshKotlinMultiplatform.Codegen.
  TypedQueries` both call, so a field can never resolve one way at compile
  time and another way in the generated Kotlin.
  """
  use Spark.Dsl.Verifier

  alias AshKotlinMultiplatform.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:kotlin_rpc])
    |> Enum.reduce_while(:ok, fn entity, acc ->
      case verify_resource(entity) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_resource(%{resource: resource} = entity) do
    entity
    |> Map.get(:typed_queries, [])
    |> Enum.reduce_while(:ok, fn typed_query, acc ->
      fields = Map.get(typed_query, :fields, []) || []

      case verify_fields(resource, fields, typed_query.name, []) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_fields(resource, fields, typed_query_name, path) do
    Enum.reduce_while(fields, :ok, fn field, acc ->
      case verify_field(resource, field, typed_query_name, path) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_field(resource, {field, nested_fields}, typed_query_name, path)
       when is_list(nested_fields) do
    verify_relationship(resource, field, nested_fields, typed_query_name, path)
  end

  defp verify_field(resource, {field, %{} = config}, typed_query_name, path) do
    verify_relationship(resource, field, Map.get(config, :fields, []), typed_query_name, path)
  end

  defp verify_field(resource, field, typed_query_name, path) do
    case ResourceInfo.resolve_typed_query_field(resource, field) do
      {:ok, _} -> :ok
      {:error, reason} -> error(resource, typed_query_name, path ++ [field], reason)
    end
  end

  defp verify_relationship(resource, field, nested_fields, typed_query_name, path) do
    case ResourceInfo.resolve_typed_query_field(resource, field) do
      {:ok, {:relationship, rel}} ->
        verify_fields(rel.destination, nested_fields, typed_query_name, path ++ [field])

      {:ok, _not_a_relationship} ->
        :ok

      {:error, reason} ->
        error(resource, typed_query_name, path ++ [field], reason)
    end
  end

  defp error(resource, typed_query_name, path, {:excluded_calculation, name}) do
    field_path = format_path(path)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Typed query #{inspect(typed_query_name)} on #{inspect(resource)} names `#{field_path}`, \
       a calculation declared `field?: false`.

       Ash never puts a `field?: false` calculation's value on the struct — it lives only in \
       `record.calculations` — so a client decoding through this typed query would always read \
       `null` for it, no matter what #{inspect(name)} computes.

       Either mark #{inspect(name)} `field?: true` (or drop the option, since that is the \
       default), or remove `#{field_path}` from `typed_query #{inspect(typed_query_name)}`'s \
       `fields`.
       """
     )}
  end

  defp error(resource, typed_query_name, path, :unknown_field) do
    field_path = format_path(path)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Typed query #{inspect(typed_query_name)} on #{inspect(resource)} names `#{field_path}`, \
       which is not a public attribute, relationship or calculation on #{inspect(resource)}.

       A private field is always refused by the RPC layer with `unknown_field`, and a name that \
       matches nothing on the resource never reaches the client as real data either way.

       Remove `#{field_path}` from `typed_query #{inspect(typed_query_name)}`'s `fields`, or \
       expose it with `public? true`.
       """
     )}
  end

  defp format_path(path), do: Enum.map_join(path, ".", &to_string/1)
end
