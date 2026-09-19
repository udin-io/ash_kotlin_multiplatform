# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.OverrideManifest do
  @moduledoc """
  A manifest module whose persisted state a test can replace at runtime.

  `config :ash_kotlin_multiplatform, manifest:` names a module, and
  `AshKotlinMultiplatform.Manifest.manifest/1` reads that module's persisted
  `:manifest` through `Spark.Dsl.Extension.get_persisted/3`, which calls
  `module.persisted/2` (`deps/spark/lib/spark/dsl/extension.ex:150`). That is
  the whole interface, so a module answering `persisted/2` is a manifest module
  as far as the request path is concerned.

  Point the config at this module and call `put/1` to serve a tampered
  `%Ash.Info.Manifest{}` — the only way to prove the request path answers from
  the manifest rather than merely carrying one. A live read cannot follow a
  decoration that exists nowhere but here.

  Keys `put/1` does not name fall through to
  `AshKotlinMultiplatform.Test.Manifest`, so `:rpc_action_lookup` keeps naming
  the real entrypoints while `:manifest` is tampered with.
  """

  @overrides :test_override_manifest

  @doc "Serve `overrides` for the persisted keys it names."
  @spec put(%{optional(atom()) => term()}) :: :ok
  def put(overrides) when is_map(overrides),
    do: Application.put_env(:ash_kotlin_multiplatform, @overrides, overrides)

  @doc "Drop every override, so every key falls through again."
  @spec clear() :: :ok
  def clear, do: Application.delete_env(:ash_kotlin_multiplatform, @overrides)

  @doc false
  def persisted(key, default \\ nil) do
    :ash_kotlin_multiplatform
    |> Application.get_env(@overrides, %{})
    |> Map.fetch(key)
    |> case do
      {:ok, value} ->
        value

      :error ->
        Spark.Dsl.Extension.get_persisted(
          AshKotlinMultiplatform.Test.Manifest,
          key,
          default
        )
    end
  end
end
