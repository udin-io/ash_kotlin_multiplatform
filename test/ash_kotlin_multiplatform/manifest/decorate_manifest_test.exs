# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.DecorateManifestTest do
  @moduledoc """
  That the decoration happened, and that the lookups are keyed by what the
  client actually sends.

  `ash_introspection`'s risk T6: the decorator skips a module it cannot load and
  says nothing, and the resource then reads live — the right answer by the slow
  path, with no signal. The core cannot watch a consumer's manifest, so the
  `decorated?/2` assertions here are this repo's half of that mitigation.
  """
  use ExUnit.Case, async: true

  alias AshIntrospection.Manifest.Custom
  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Test

  @namespace :ash_kotlin_multiplatform

  defp manifest, do: Manifest.manifest(Test.Manifest)
  defp undecorated, do: Spark.Dsl.Extension.get_persisted(Test.Manifest, :undecorated_manifest)

  describe "decorated?/2 — the T6 watch" do
    test "every resource in the manifest is decorated" do
      for resource <- manifest().resources do
        assert Custom.decorated?(resource, @namespace),
               "#{inspect(resource.module)} reached the manifest bare and will read live"
      end
    end

    test "every relationship on every resource is decorated" do
      for resource <- manifest().resources,
          {name, relationship} <- resource.relationships do
        assert Custom.decorated?(relationship, @namespace),
               "#{inspect(resource.module)}.#{name} is undecorated"
      end
    end

    test "every entrypoint is decorated" do
      for entrypoint <- manifest().entrypoints do
        assert Custom.decorated?(entrypoint, @namespace)
      end
    end

    test "the manifest itself is decorated" do
      assert Custom.decorated?(manifest(), @namespace)
    end
  end

  describe "what the decoration carries" do
    test "the live Ash attribute structs, not manifest fields" do
      attributes = Custom.attributes(resource(Test.Todo), @namespace)

      assert Enum.any?(attributes, &match?(%Ash.Resource.Attribute{name: :id}, &1))
    end

    test "client-facing field names under the configured formatter" do
      todo = resource(Test.Todo)

      assert Custom.formatted_field_name(todo, :completed_at, :camel_case, @namespace) ==
               "completedAt"

      assert Custom.formatted_field_name(todo, :completed_at, :pascal_case, @namespace) ==
               "CompletedAt"

      assert Custom.formatted_field_name(todo, :completed_at, :snake_case, @namespace) ==
               "completed_at"
    end

    test "every action on the resource" do
      names = Test.Todo |> resource() |> Custom.actions(@namespace) |> Enum.map(& &1.name)

      assert :read in names
      assert :create in names
    end
  end

  describe "the undecorated manifest is left alone" do
    test "no resource on it is decorated" do
      for resource <- undecorated().resources do
        refute Custom.decorated?(resource, @namespace)
      end
    end
  end

  describe "rpc_action_lookup" do
    test "is keyed by the client-facing rpc_action name" do
      lookup = Manifest.rpc_action_lookup(Test.Manifest)

      assert Map.has_key?(lookup, "list_todos")
      assert Map.has_key?(lookup, "create_author")
      assert lookup["list_todos"].resource == Test.Todo
    end

    # R1. Both rpc_actions sit on Test.Todo's :read. Keying by
    # {resource, action} — which is all the core decorator's :entrypoint_name
    # callback can see — collapses them into one, and the core raises rather
    # than pick a winner. Keying off entrypoint.config keeps both.
    test "two rpc_actions over one action are two distinct entries" do
      lookup = Manifest.rpc_action_lookup(Test.Manifest)

      assert Map.has_key?(lookup, "list_todos")
      assert Map.has_key?(lookup, "get_todo")

      list = lookup["list_todos"]
      get = lookup["get_todo"]

      assert list.resource == get.resource
      assert list.action.name == get.action.name
      refute list == get
    end

    test "carries the domain each action must run through" do
      lookup = Manifest.rpc_action_lookup(Test.Manifest)

      assert lookup["list_todos"].config.ash_kotlin_multiplatform.domain == Test.Domain
    end

    test "holds one entry per rpc_action in the DSL" do
      declared =
        Test.Domain
        |> AshKotlinMultiplatform.Rpc.Info.kotlin_rpc()
        |> Enum.flat_map(& &1.rpc_actions)
        |> Enum.map(&to_string(&1.name))
        |> MapSet.new()

      assert MapSet.new(Map.keys(Manifest.rpc_action_lookup(Test.Manifest))) == declared
    end
  end

  describe "typed_query_lookup" do
    test "is keyed by the typed_query name" do
      lookup = Manifest.typed_query_lookup(Test.ScopedManifest)

      assert Map.has_key?(lookup, "book_titles")
      assert lookup["book_titles"].resource == Test.Book
    end

    test "a typed query and an rpc_action over one action are separate entrypoints" do
      typed = Manifest.typed_query_lookup(Test.ScopedManifest)["book_titles"]
      rpc = Manifest.rpc_action_lookup(Test.ScopedManifest)["scoped_list_books"]

      assert typed.action.name == rpc.action.name
      refute typed == rpc
    end

    test "is empty when no domain declares one" do
      assert Manifest.typed_query_lookup(Test.Manifest) == %{}
    end
  end

  describe "the :domains option" do
    test "scopes the manifest to exactly the domains named" do
      modules = Test.ScopedManifest |> Manifest.manifest() |> Map.fetch!(:resources)
      modules = Enum.map(modules, & &1.module)

      assert Test.Book in modules
      refute Test.Todo in modules
    end
  end

  defp resource(module) do
    Enum.find(manifest().resources, &(&1.module == module)) ||
      flunk("#{inspect(module)} is not in the manifest")
  end
end
