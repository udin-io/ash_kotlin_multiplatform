# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.RpcConfigCollector do
  @moduledoc """
  Collects RPC configuration from domains including resources, actions, and typed queries.
  """

  alias AshKotlinMultiplatform.Rpc.Info

  @doc """
  Gets all RPC resources and their actions from an OTP application.

  Returns a list of tuples: `{resource, action, rpc_action}`
  """
  def get_rpc_resources_and_actions(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = Info.kotlin_rpc(domain)

      Enum.flat_map(rpc_config, fn %{resource: resource, rpc_actions: rpc_actions} ->
        Enum.map(rpc_actions, fn rpc_action ->
          action = Ash.Resource.Info.action(resource, rpc_action.action)
          {resource, action, rpc_action}
        end)
      end)
    end)
  end

  @doc """
  Gets all typed queries from an OTP application.

  Returns a list of tuples: `{resource, action, typed_query}`
  """
  def get_typed_queries(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = Info.kotlin_rpc(domain)

      Enum.flat_map(rpc_config, fn %{resource: resource, typed_queries: typed_queries} ->
        Enum.map(typed_queries, fn typed_query ->
          action = Ash.Resource.Info.action(resource, typed_query.action)
          {resource, action, typed_query}
        end)
      end)
    end)
  end

  @doc """
  Gets all RPC-configured resources from an OTP application.

  Returns a list of unique resource modules.
  """
  def get_rpc_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      Info.kotlin_rpc(domain)
      |> Enum.map(fn %{resource: r} -> r end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Gets all RPC configurations grouped by resource.

  Returns a list of maps with resource and their actions/queries.
  """
  def get_rpc_configs(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(&Info.kotlin_rpc/1)
  end

  @doc """
  Gets all domains that have RPC configuration.
  """
  def get_rpc_domains(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.filter(fn domain ->
      case Info.kotlin_rpc(domain) do
        [] -> false
        _ -> true
      end
    end)
  end
end
