# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.SharedJsonTest do
  @moduledoc """
  Every generated encode and decode path must go through `ashRpcJson`, the one
  `Json` that carries the `SerializersModule`.

  Issue #54: `createHttpClient()` registered the module and three other paths did
  not — `RpcResult.dataAs()` and the Phoenix channel client each built their own
  `Json`, and every request payload encoded through the `Json` companion, which
  is `Json.Default` and carries no module. A `@Contextual` field down any of
  those paths threw `SerializationException` at runtime while compiling clean.

  Counting `Json {` and the bare companion is the assertion that holds: naming
  the paths one by one is what let three of them drift apart in the first place.
  """
  # Not async: the whole-file tests swap :ash_domains, which is global.
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic

  setup do
    previous = Application.get_env(:ash_kotlin_multiplatform, :ash_domains)

    Application.put_env(:ash_kotlin_multiplatform, :ash_domains, [
      AshKotlinMultiplatform.Test.Domain
    ])

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:ash_kotlin_multiplatform, :ash_domains)
        value -> Application.put_env(:ash_kotlin_multiplatform, :ash_domains, value)
      end
    end)

    :ok
  end

  defp generated do
    {:ok, kotlin} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform, with_filters: true)
    kotlin
  end

  # `Json.Default` under its companion spelling. Rejects the declaration of
  # `ashRpcJson` itself and the type ascriptions that legitimately name Json.
  defp companion_uses(kotlin) do
    kotlin
    |> String.split("\n")
    |> Enum.filter(&Regex.match?(~r/(?<![A-Za-z0-9_.])Json\.(encode|decode|parse)/, &1))
  end

  describe "the generated file" do
    test "declares exactly one Json" do
      kotlin = generated()

      assert length(String.split(kotlin, "Json {")) - 1 == 1
      assert kotlin =~ "val ashRpcJson: Json = Json {"
    end

    test "registers the SerializersModule on that one Json" do
      kotlin = generated()

      [_before, after_decl] = String.split(kotlin, "val ashRpcJson: Json = Json {", parts: 2)
      [body, _rest] = String.split(after_decl, "\n}\n", parts: 2)

      assert body =~ "serializersModule = SerializersModule"
    end

    test "encodes and decodes through it rather than through the Json companion" do
      assert companion_uses(generated()) == []
    end
  end

  describe "createHttpClient" do
    test "installs the shared Json rather than building its own" do
      kotlin = KotlinStatic.generate_http_client_factory()

      assert kotlin =~ "json(ashRpcJson)"
      refute kotlin =~ "Json {"
    end
  end

  describe "RpcResult.dataAs" do
    test "decodes through the shared Json" do
      kotlin = KotlinStatic.generate_generic_result_types()

      assert kotlin =~ "ashRpcJson.decodeFromJsonElement<T>(it)"
      refute kotlin =~ "Json {"
    end
  end

  describe "the Phoenix channel client" do
    test "holds no Json of its own" do
      kotlin = AshKotlinMultiplatform.Rpc.Codegen.PhoenixChannel.generate()

      refute kotlin =~ "Json {"
      refute kotlin =~ "private val json"
      assert kotlin =~ "ashRpcJson.decodeFromJsonElement<RpcResult>(resp)"
    end
  end
end
