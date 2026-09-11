# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Codegen.RpcActionOptionsCodegenTest do
  @moduledoc """
  What the `rpc_action` options of #25 change in the emitted Kotlin.

  The config class and the payload builder are a pair: the generated function
  body reads `config.getBy`, `config.filter` and `config.sort`, and the class it
  reads from is built separately. When the two disagreed the generated Kotlin
  referenced a property that was never declared, which is the defect the
  compile gate exists for — so both sides are asserted here rather than one.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Codegen.Helpers.{ConfigBuilder, PayloadBuilder}
  alias AshKotlinMultiplatform.Test.{Author, Book}

  defp context(resource, action_name, rpc_action) do
    action = Ash.Resource.Info.action(resource, action_name)
    ConfigBuilder.get_action_context(resource, action, rpc_action)
  end

  defp config(resource, action_name, rpc_action, rpc_name) do
    action = Ash.Resource.Info.action(resource, action_name)
    ConfigBuilder.generate_config_type(resource, action, rpc_action, rpc_name)
  end

  defp payload(resource, action_name, rpc_action, rpc_name) do
    PayloadBuilder.build_payload_code(rpc_name, context(resource, action_name, rpc_action))
  end

  describe "get_by" do
    test "declares a typed GetBy class and a required config property" do
      kotlin = config(Author, :read, %{get_by: [:id]}, :fetch_author)

      assert kotlin =~ "@Serializable"
      assert kotlin =~ "data class FetchAuthorGetBy("
      assert kotlin =~ "val id: String"
      assert kotlin =~ "val getBy: FetchAuthorGetBy"
    end

    test "sends the lookup under getBy" do
      assert payload(Author, :read, %{get_by: [:id]}, :fetch_author) =~
               ~s|put("getBy", ashRpcJson.encodeToJsonElement(config.getBy))|
    end

    test "makes the read a get, so it drops filter, sort and page" do
      kotlin = config(Author, :read, %{get_by: [:id]}, :fetch_author)

      refute kotlin =~ "val filter:"
      refute kotlin =~ "val sort:"
      refute kotlin =~ "val page:"
    end

    test "get? alone makes the read a get with no lookup class" do
      kotlin = config(Author, :read, %{get?: true}, :current_author)

      assert context(Author, :read, %{get?: true}).is_get_action
      refute kotlin =~ "GetBy"
      refute kotlin =~ "val filter:"
    end

    test "an action that configures none declares no GetBy" do
      refute config(Author, :read, %{}, :list_authors) =~ "GetBy"
    end
  end

  describe "enable_filter? and enable_sort?" do
    test "both are declared by default" do
      kotlin = config(Book, :read, %{}, :list_books)

      assert kotlin =~ "val filter: Map<String, JsonElement>? = null"
      assert kotlin =~ "val sort: String? = null"
    end

    test "enable_filter? false drops filter and keeps sort" do
      kotlin = config(Book, :read, %{enable_filter?: false}, :list_books_unfiltered)

      refute kotlin =~ "val filter:"
      assert kotlin =~ "val sort: String? = null"
    end

    test "enable_sort? false drops sort and keeps filter" do
      kotlin = config(Book, :read, %{enable_sort?: false}, :list_books_fixed_order)

      assert kotlin =~ "val filter: Map<String, JsonElement>? = null"
      refute kotlin =~ "val sort:"
    end

    test "the payload stops sending what the config stopped declaring" do
      unfiltered = payload(Book, :read, %{enable_filter?: false}, :list_books_unfiltered)
      unsorted = payload(Book, :read, %{enable_sort?: false}, :list_books_fixed_order)

      refute unfiltered =~ "config.filter"
      assert unfiltered =~ "config.sort"

      assert unsorted =~ "config.filter"
      refute unsorted =~ "config.sort"
    end
  end

  describe "identities" do
    test "the default addresses an update by primary key" do
      assert context(Author, :destroy, %{}).identities == [:_primary_key]
    end

    test "an empty list drops the identity property and the payload key" do
      kotlin = config(Author, :destroy, %{identities: []}, :destroy_author)

      assert context(Author, :destroy, %{identities: []}).identities == []
      refute kotlin =~ "val identity:"
      refute payload(Author, :destroy, %{identities: []}, :destroy_author) =~ ~s|put("identity"|
    end

    test "a read never takes an identity, whatever the option says" do
      assert context(Author, :read, %{identities: [:_primary_key]}).identities == []
    end
  end
end
