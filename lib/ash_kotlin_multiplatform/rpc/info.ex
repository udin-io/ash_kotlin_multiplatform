# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Info do
  @moduledoc """
  Introspection helpers for AshKotlinMultiplatform.Rpc DSL.
  """

  use Spark.InfoGenerator, extension: AshKotlinMultiplatform.Rpc, sections: [:kotlin_rpc]

  @doc """
  Returns all resources configured in the kotlin_rpc section of a domain.
  """
  def kotlin_rpc(domain) do
    Spark.Dsl.Extension.get_entities(domain, [:kotlin_rpc])
  end

  @doc """
  Returns all RPC resources from all domains in the given OTP app.
  """
  def get_rpc_resources(otp_app) do
    otp_app
    |> Ash.Info.domains()
    |> Enum.flat_map(fn domain ->
      rpc_config = kotlin_rpc(domain)
      Enum.map(rpc_config, fn %{resource: resource} -> resource end)
    end)
    |> Enum.uniq()
  end
end
