# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest do
  @moduledoc """
  Hands the manifest `BuildManifest` persisted to
  `AshIntrospection.Manifest.Decorator.decorate/3`, re-persists the decorated
  result, and builds the two lookups the request path keys on.

  Everything `decorate/3` writes lands under `custom.:ash_kotlin_multiplatform`
  and is read back through `AshIntrospection.Manifest.Custom` with that same
  namespace. Each generator decorating under its own key is the split
  `ash_introspection` issue 23 exists to enable.

  The config map is `AshKotlinMultiplatform.Rpc.Pipeline.build_config/0` — the
  same callbacks the pipeline threads through per request, called here once per
  field at compile time instead.

  ## Why `:entrypoint_name` is deliberately absent

  `decorate/3` accepts an `:entrypoint_name` callback and, given one, builds a
  global `entrypoint_lookup` keyed by the name it returns. The callback receives
  `(resource, action_name)` and nothing else —
  `AshIntrospection.Manifest.Decorator.entrypoint_client_name/2` never reads
  `entrypoint.config`.

  This library maps several client-facing operations onto one Ash action.
  `AshKotlinMultiplatform.Rpc`'s own moduledoc exposes `MyApp.Todo`'s `:read`
  twice, as `list_todos` and `get_todo`, and this repo's test domain does the
  same. Both produce entrypoints with identical `(resource, action)`, so any
  such callback returns one name for both and the decorator raises
  `ArgumentError` — two entrypoints claiming one client-facing name — at
  compile time. Supplying the callback would make the library's own documented
  example fail to compile.

  So we pass no `:entrypoint_name`, leave the core's `entrypoint_lookup` empty,
  and build `:rpc_action_lookup` and `:typed_query_lookup` here off
  `entrypoint.config`, which is the only place the client-facing name exists.

  **Do not key an entrypoint by `{resource, action}` anywhere downstream.** That
  pair is not unique in this library.
  """

  use Spark.Dsl.Transformer

  alias AshIntrospection.Manifest.Decorator
  alias AshKotlinMultiplatform.Manifest.Entrypoints
  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshKotlinMultiplatform.Manifest.Transformers.BuildManifest), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    case Transformer.get_persisted(dsl_state, :manifest) do
      nil ->
        {:ok, dsl_state}

      manifest ->
        decorated =
          Decorator.decorate(
            manifest,
            Entrypoints.namespace(),
            AshKotlinMultiplatform.Rpc.Pipeline.build_config()
          )

        {:ok,
         dsl_state
         |> Transformer.persist(:manifest, decorated)
         |> Transformer.persist(:rpc_action_lookup, lookup(decorated, :rpc_action))
         |> Transformer.persist(:typed_query_lookup, lookup(decorated, :typed_query))}
    end
  end

  # One pass per key rather than one pass building both, because an entrypoint
  # carries exactly one of them and the two maps are read independently.
  defp lookup(%Ash.Info.Manifest{entrypoints: entrypoints}, key) do
    namespace = Entrypoints.namespace()

    Enum.reduce(entrypoints, %{}, fn entrypoint, acc ->
      case entrypoint.config do
        %{^namespace => %{^key => %{name: name}}} ->
          put_unique(acc, to_string(name), entrypoint, key)

        _ ->
          acc
      end
    end)
  end

  # Two operations answering to one name is a request the runtime cannot route,
  # and keeping either one silently sends half the calls to the wrong action.
  # The DSL cannot catch it: the names live in different domains' kotlin_rpc
  # blocks, and no verifier sees more than one domain.
  defp put_unique(acc, name, entrypoint, key) do
    case Map.get(acc, name) do
      nil ->
        Map.put(acc, name, entrypoint)

      existing ->
        raise Spark.Error.DslError,
          module: __MODULE__,
          path: [:kotlin_rpc, key],
          message: """
          Two #{key} entries claim the client-facing name #{inspect(name)}:

            #{inspect(existing.resource)}.#{existing.action.name}
            #{inspect(entrypoint.resource)}.#{entrypoint.action.name}

          The name a client sends must be unique across every domain in the
          manifest, not just within one kotlin_rpc block.
          """
    end
  end
end
