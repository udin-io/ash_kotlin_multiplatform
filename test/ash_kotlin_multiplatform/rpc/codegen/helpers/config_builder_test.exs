# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.Helpers.ConfigBuilderTest do
  @moduledoc """
  The generated function body reads `config.metadataFields` for every action that
  exposes metadata (see `PayloadBuilder.build_payload_code/3`). The Config class it
  reads from is built here, so the two must agree — when they did not, the
  generated Kotlin referenced a property that was never declared.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Codegen.Helpers.ConfigBuilder
  alias AshKotlinMultiplatform.Test.Event

  defp config_for(action_name, rpc_name) do
    action = Ash.Resource.Info.action(Event, action_name)
    ConfigBuilder.generate_config_type(Event, action, %{}, rpc_name)
  end

  describe "generate_config_type/4" do
    test "declares metadataFields for an action that exposes metadata" do
      assert config_for(:register, :register_event) =~ "val metadataFields: List<String>? = null"
    end

    test "omits metadataFields for an action with no metadata" do
      refute config_for(:create, :create_event) =~ "metadataFields"
    end
  end
end
