# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.BuildManifestTest do
  @moduledoc """
  What `BuildManifest` puts on the DSL state, read back the way a consumer reads
  it: through `Spark.Dsl.Extension.get_persisted/3` on a compiled module.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Test

  defp manifest, do: AshKotlinMultiplatform.Manifest.manifest(Test.Manifest)
  defp undecorated, do: Spark.Dsl.Extension.get_persisted(Test.Manifest, :undecorated_manifest)

  describe "the persisted manifest" do
    test "is an %Ash.Info.Manifest{}" do
      assert %Ash.Info.Manifest{} = manifest()
    end

    test "carries every resource named in a kotlin_rpc block" do
      modules = Enum.map(manifest().resources, & &1.module)

      for resource <- [Test.Author, Test.Book, Test.Event, Test.Todo, Test.User] do
        assert resource in modules,
               "#{inspect(resource)} is in a kotlin_rpc block but not in the manifest"
      end
    end

    test "carries a resource that is only reachable through a relationship" do
      # Test.Secret is published to no rpc_action. It is reachable only by
      # walking Author.secrets, so its presence proves reachability ran.
      modules = Enum.map(manifest().resources, & &1.module)
      assert Test.Secret in modules
    end
  end

  describe "entrypoints" do
    test "one per rpc_action, carrying the rpc_action and its domain" do
      entrypoint = entrypoint_named(:list_todos)

      assert entrypoint.resource == Test.Todo
      assert entrypoint.action.name == :read
      assert entrypoint.config.ash_kotlin_multiplatform.domain == Test.Domain
      assert entrypoint.config.ash_kotlin_multiplatform.rpc_action.name == :list_todos
      assert is_nil(Map.get(entrypoint.config.ash_kotlin_multiplatform, :typed_query))
    end

    # R1 from the architecture brief. `AshKotlinMultiplatform.Rpc`'s own
    # moduledoc exposes one action twice, and
    # `AshIntrospection.Manifest.Decorator` raises on two entrypoints claiming
    # one client-facing name. This is the test that pins why we never pass
    # `:entrypoint_name` to `decorate/3`.
    test "two rpc_actions on one resource and action produce two distinct entrypoints" do
      list = entrypoint_named(:list_todos)
      get = entrypoint_named(:get_todo)

      assert list.resource == get.resource
      assert list.action.name == get.action.name
      refute list == get

      assert list.config.ash_kotlin_multiplatform.rpc_action.name == :list_todos
      assert get.config.ash_kotlin_multiplatform.rpc_action.name == :get_todo
    end

    test "no entrypoint carries a client_name from the core decorator" do
      # We build the lookups ourselves off `config`, so `:entrypoint_name` is
      # deliberately absent from the config map handed to `decorate/3`.
      for entrypoint <- manifest().entrypoints do
        assert is_nil(AshIntrospection.Manifest.Custom.entrypoint_client_name(entrypoint))
      end
    end
  end

  describe "generator options" do
    # R3 from the brief. `Ash.Info.Manifest.Generator.generate/1` defaults
    # `:include_private_relationships?` to false, which is how the core shipped
    # a nil `relationship/3` in stage 1. Test.Book.editor is private.
    test "a private belongs_to is in the manifest" do
      book = Enum.find(manifest().resources, &(&1.module == Test.Book))

      assert Map.has_key?(book.relationships, :editor),
             "generate/1 was called without include_private_relationships?: true"

      # The public one is still there, so the option widened the set rather
      # than replacing it.
      assert Map.has_key?(book.relationships, :author)
    end

    test "and is absent from a manifest built with the generator's defaults" do
      # The oracle for the assertion above: without this, that test would keep
      # passing if `generate/1` ever changed its default, and would tell us
      # nothing about whether the option is what puts :editor there.
      {:ok, default} =
        Ash.Info.Manifest.Generator.generate(
          otp_app: :ash_kotlin_multiplatform,
          action_entrypoints: [{Test.Book, :read}]
        )

      book = Enum.find(default.resources, &(&1.module == Test.Book))

      refute Map.has_key?(book.relationships, :editor)
      assert Map.has_key?(book.relationships, :author)
    end
  end

  describe "the undecorated manifest" do
    test "is persisted alongside the decorated one" do
      assert %Ash.Info.Manifest{} = undecorated()
    end

    test "has no ash_kotlin_multiplatform key under custom" do
      refute Map.has_key?(undecorated().custom, :ash_kotlin_multiplatform)
    end
  end

  defp entrypoint_named(name) do
    Enum.find(manifest().entrypoints, fn entrypoint ->
      case entrypoint.config do
        %{ash_kotlin_multiplatform: %{rpc_action: %{name: ^name}}} -> true
        _ -> false
      end
    end) || flunk("no entrypoint for rpc_action #{inspect(name)}")
  end
end
