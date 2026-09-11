# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.TypedResultsTest do
  @moduledoc """
  Every generated RPC function returns `RpcResult<T>` named for its own action.

  Before #22 all fifteen returned the same `RpcResult` with `data: JsonElement?`,
  while the generator emitted a `{Action}Result` sealed class per action that
  nothing referenced and a `{Action}OffsetResult` family that could not have
  decoded the un-paginated call. `FunctionCore.determine_return_type/1` computed
  the answer and had no caller.

  These assertions are the cheap half — they prove the generator names the type.
  The expensive half is `test/fixtures/kotlin_compile`, which compiles it and
  then decodes a real `Rpc.Runner` response into it.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Codegen.FunctionGenerators.HttpRenderer
  alias AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic
  alias AshKotlinMultiplatform.Rpc.Codegen.PhoenixChannel
  alias AshKotlinMultiplatform.Test.{Author, Event, Todo}

  defp signature(resource, action_name, rpc_name, rpc_action \\ %{}) do
    action = Ash.Resource.Info.action(resource, action_name)

    resource
    |> HttpRenderer.render_execution_function(action, rpc_action, rpc_name)
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, "): RpcResult"))
  end

  describe "the type a generated function returns" do
    test "a create returns the resource" do
      assert signature(Author, :create, :create_author) =~ "): RpcResult<Author> {"
    end

    test "a get action returns the resource, not a nullable one" do
      # `data` is already `T?` on RpcResult, so `Author?` would only add a
      # second question mark.
      assert signature(Author, :by_id, :get_author) =~ "): RpcResult<Author> {"
    end

    test "a destroy returns the destroyed record, not a boolean" do
      # `Pipeline.execute_destroy_action/3` bulk-destroys with
      # `return_records?: true` and hands back the record.
      assert signature(Author, :destroy, :destroy_author) =~ "): RpcResult<Author> {"
    end

    test "a read that supports pagination returns a page" do
      # Ash 3 defaults every read to offset and keyset pagination, so this is
      # the common branch. `AshPage` reads the bare list too.
      assert signature(Author, :read, :list_authors) =~ "): RpcResult<AshPage<Author>> {"
    end

    test "a mutation that exposes metadata returns the envelope the server wraps it in" do
      assert signature(Event, :register, :register_event) =~
               "): RpcResult<AshMetadata<Event, RegisterEventMetadata>> {"
    end

    test "a mutation with the metadata switched off returns the record itself" do
      assert signature(Event, :register, :register_event, %{show_metadata: false}) =~
               "): RpcResult<Event> {"
    end

    test "the resource's configured type name is the one used" do
      assert signature(Todo, :create, :create_todo) =~ "): RpcResult<Todo> {"
    end
  end

  describe "RpcResult" do
    test "is generic over what the action returns" do
      kotlin = KotlinStatic.generate_generic_result_types()

      assert kotlin =~ "data class RpcResult<T>("
      assert kotlin =~ "val data: T? = null"
    end

    test "keeps dataAs() for an untyped result" do
      # The channel client takes the action name as a string, so it has no type
      # to name. Through `ashRpcJson`, never a fresh Json (#54).
      kotlin = KotlinStatic.generate_generic_result_types()

      assert kotlin =~ "inline fun <reified T> RpcResult<JsonElement>.dataAs(): T?"
      assert kotlin =~ "ashRpcJson.decodeFromJsonElement<T>(it)"
    end

    test "the channel client returns the untyped one" do
      kotlin = PhoenixChannel.generate()

      assert kotlin =~ "): RpcResult<JsonElement> {"
      assert kotlin =~ "decodeFromJsonElement<RpcResult<JsonElement>>(resp)"
      refute kotlin =~ ~r/RpcResult\(/
    end
  end

  describe "the orphaned per-action types are gone" do
    test "no module emits a {Action}Result sealed class" do
      refute Code.ensure_loaded?(AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.ResultTypes)
    end

    test "the full generated file declares no per-action pagination result" do
      {:ok, kotlin} =
        AshKotlinMultiplatform.Rpc.Codegen.generate_kotlin_code(:ash_kotlin_multiplatform, [])

      refute kotlin =~ "ListAuthorsResult"
      refute kotlin =~ "ListAuthorsOffsetResult"
      refute kotlin =~ "ListAuthorsPaginatedResult"
      assert kotlin =~ "data class AshPage<T>("
      assert kotlin =~ "data class AshMetadata<T, M>("
    end
  end
end
