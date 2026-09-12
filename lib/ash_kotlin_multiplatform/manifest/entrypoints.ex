# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.Entrypoints do
  @moduledoc """
  Maps this library's `kotlin_rpc` DSL onto the entrypoint list
  `Ash.Info.Manifest.Generator.generate/1` takes.

  An `%Ash.Info.Manifest.Entrypoint{}` carries a resource and an action and
  nothing else. Everything this library needs to answer a request — which
  `rpc_action` or `typed_query` the client named, and which domain to run it
  through — travels in the entrypoint's `config` map under the
  `:ash_kotlin_multiplatform` key, which the generator passes through opaquely.

  The domain matters because the manifest does not carry one and
  `AshKotlinMultiplatform.Rpc.Runner` needs it to execute the action.

  ## One action, several entrypoints

  `rpc_action :list_todos, :read` and `rpc_action :get_todo, :read` are two
  client-facing operations over one Ash action, and
  `AshKotlinMultiplatform.Rpc`'s own moduledoc documents that shape. The
  generator makes one entrypoint per entry here and preserves duplicates
  (`build_entrypoints/3` in `deps/ash/lib/ash/info/manifest/generator.ex`), so
  both survive with different `config` maps.

  That is also why nothing downstream may key an entrypoint by
  `{resource, action}`. See
  `AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest`.
  """

  alias AshKotlinMultiplatform.Rpc.Codegen.RpcConfigCollector

  @namespace :ash_kotlin_multiplatform

  @doc "The namespace every `custom` and `config` payload of ours is written under."
  @spec namespace() :: atom()
  def namespace, do: @namespace

  @doc "Every resource named in a `kotlin_rpc` block across `domains`, deduplicated."
  @spec rpc_resources([module()]) :: [module()]
  def rpc_resources(domains) when is_list(domains),
    do: RpcConfigCollector.get_rpc_resources(domains)

  @doc """
  The `:action_entrypoints` argument for
  `Ash.Info.Manifest.Generator.generate/1`.

  One entry per `rpc_action`, one per `typed_query`, plus a reachability root
  for every resource in a `kotlin_rpc` block that has neither — otherwise a
  resource published with no actions would be absent from the manifest, and
  codegen would have nothing to emit for it.

  A `typed_query` gets an entrypoint even when its action is already exposed as
  an `rpc_action`, so the manifest's `action_lookup` carries it.
  """
  @spec action_entrypoints([module()], [module()]) :: [
          %{resource: module(), action: atom(), config: map()} | {module(), atom()}
        ]
  def action_entrypoints(domains, rpc_resources) when is_list(domains) do
    entries =
      domains
      |> Enum.flat_map(fn domain ->
        domain
        |> AshKotlinMultiplatform.Rpc.Info.kotlin_rpc()
        |> Enum.flat_map(&entries_for_resource(&1, domain))
      end)

    entries ++ reachability_roots(entries, rpc_resources)
  end

  defp entries_for_resource(resource_config, domain) do
    %{resource: resource, rpc_actions: rpc_actions, typed_queries: typed_queries} =
      resource_config

    rpc_entries =
      Enum.map(rpc_actions, fn rpc_action ->
        entry(resource, rpc_action.action, domain, resource_config, rpc_action: rpc_action)
      end)

    typed_query_entries =
      Enum.map(typed_queries, fn typed_query ->
        entry(resource, typed_query.action, domain, resource_config, typed_query: typed_query)
      end)

    rpc_entries ++ typed_query_entries
  end

  defp entry(resource, action, domain, resource_config, extra) do
    payload =
      extra
      |> Map.new()
      |> Map.merge(%{domain: domain, resource_config: resource_config})

    %{resource: resource, action: action, config: %{@namespace => payload}}
  end

  # `:__reachability_root__` names no real action, so the generator's
  # `build_entrypoints/3` drops it from `entrypoints` while reachability still
  # treats the resource as a root. That is how a resource with no rpc_action
  # reaches `manifest.resources` without inventing an entrypoint for it.
  defp reachability_roots(entries, rpc_resources) do
    covered = MapSet.new(entries, & &1.resource)

    rpc_resources
    |> Enum.reject(&MapSet.member?(covered, &1))
    |> Enum.map(&{&1, :__reachability_root__})
  end
end
