# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerManifestSourceTest do
  @moduledoc """
  The manifest is the request path's source of truth, not a passenger on it
  (`ash_introspection#23` stage 5a, PR 4).

  Carrying a manifest and reading it are different claims, and only the second
  is worth asserting. A test that configures a manifest agreeing with the live
  domain passes whichever one the code reads. So every test here points
  `config :ash_kotlin_multiplatform, manifest:` at a manifest that DISAGREES
  with live introspection, and asserts the response follows the manifest:

    * a manifest scoped to one domain, which names no `list_todos` at all,
    * a decoration with one payload rewritten, which no live read can reproduce.

  Synchronous, because each test repoints that config key and every other test
  reads it. ExUnit runs synchronous modules after the asynchronous ones.
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Rpc.Runner
  alias AshKotlinMultiplatform.Test

  @namespace :ash_kotlin_multiplatform

  setup do
    original = Application.fetch_env!(:ash_kotlin_multiplatform, :manifest)

    on_exit(fn ->
      Test.OverrideManifest.clear()
      Application.put_env(:ash_kotlin_multiplatform, :manifest, original)
    end)

    :ok
  end

  describe "a manifest scoped to one domain" do
    setup do
      Application.put_env(:ash_kotlin_multiplatform, :manifest, Test.ScopedManifest)
      :ok
    end

    test "an rpc_action it does not name is action_not_found" do
      assert [error] = errors(run(%{"action" => "list_todos"}))
      assert error["type"] == "action_not_found"
      assert error["message"] == "RPC action 'list_todos' not found"
    end

    # The other half of the claim above. Without it the first test passes on a
    # request path that answers `action_not_found` to everything.
    test "an rpc_action it does name runs, though no configured domain declares it" do
      refute Test.ScopedDomain in Ash.Info.domains(:ash_kotlin_multiplatform)

      assert %{"success" => true, "data" => books} =
               run(%{"action" => "scoped_list_books", "fields" => ["id"]})

      assert is_list(books)
    end

    test "the live domain scan this replaced would have answered the opposite" do
      names =
        for %{rpc_actions: rpc_actions} <-
              AshKotlinMultiplatform.Rpc.Info.kotlin_rpc(Test.Domain),
            rpc_action <- rpc_actions,
            do: to_string(rpc_action.name)

      assert "list_todos" in names
      refute Map.has_key?(Manifest.rpc_action_lookup(Test.ScopedManifest), "list_todos")
    end
  end

  describe "a tampered decoration" do
    test "a public attribute the decoration no longer lists is not returned" do
      tamper(Test.Author, fn payload ->
        Map.update!(payload, :public_attributes, &Enum.reject(&1, fn a -> a.name == :email end))
      end)

      create_author("Tampered Attributes", "tampered-attributes@example.com")
      author = find_author("Tampered Attributes")

      assert Map.has_key?(author, "name")
      refute Map.has_key?(author, "email")
    end

    test "a decorated read action marked get? returns one record, not a list" do
      email = "tampered-read@example.com"
      create_author("Tampered Read", email)

      tamper(Test.Author, &tamper_by_name(&1, :actions, :read, fn a -> %{a | get?: true} end))

      assert %{"success" => true, "data" => author} =
               run(%{
                 "action" => "list_authors",
                 "fields" => ["name"],
                 "filter" => %{"email" => email}
               })

      assert author == %{"name" => "Tampered Read"}
    end

    test "a decorated create action whose type says read cannot be validated" do
      tamper(Test.Author, &tamper_by_name(&1, :actions, :create, fn a -> %{a | type: :read} end))

      response =
        Runner.validate_action(:ash_kotlin_multiplatform, %{
          "action" => "create_author",
          "input" => %{"name" => "Tampered Create", "email" => "tampered-create@example.com"}
        })

      assert [error] = errors(response)
      assert error["type"] == "unsupported"
    end

    test "a decorated map attribute given declared fields stops being untyped" do
      tamper(
        Test.Todo,
        &tamper_by_name(&1, :attributes, :metadata, fn attribute ->
          %{attribute | constraints: [fields: [notify_by_email: [type: :boolean]]]}
        end)
      )

      assert %{"success" => true, "data" => todo} =
               run(%{
                 "action" => "create_todo",
                 "input" => %{
                   "title" => "Tampered Map",
                   "metadata" => %{"notifyByEmail" => true}
                 }
               })

      # Untyped, the key is caller data: snake_cased on the way in and never
      # renamed on the way out, so it comes back `notify_by_email` (#71). The
      # decoration says the field is declared, so both halves rename it.
      assert todo["metadata"] == %{"notifyByEmail" => true}
    end
  end

  # `BuildManifest` passes `include_private_relationships?: true`
  # (`build_manifest.ex:69`), so `Book.editor` — `public? false` — is in this
  # library's manifest. `%Ash.Info.Manifest.Relationship{}` records no
  # visibility, so `public_relationship/3` reported it as public whenever it
  # read the manifest's own relationship map. `ash_introspection` 0.5.3 fixed
  # that by reading `public?` off the decorated record, and this PR is what
  # makes the path reachable, so the fix is pinned from this side too.
  describe "a private relationship the manifest carries" do
    test "is not selectable through the request path" do
      assert [error] =
               errors(run(%{"action" => "list_books", "fields" => [%{"editor" => ["id"]}]}))

      assert error["message"] =~ "editor"
    end

    test "reads as a relationship but not as a public one" do
      config = AshKotlinMultiplatform.Rpc.Pipeline.request_config()

      assert %{name: :editor} =
               AshIntrospection.ResourceInfo.relationship(Test.Book, :editor, config)

      refute AshIntrospection.ResourceInfo.public_relationship(Test.Book, :editor, config)
    end

    test "is in the manifest, and decorated as private" do
      book =
        Manifest.manifest()
        |> Map.fetch!(:resources)
        |> Enum.find(&(&1.module == Test.Book))

      assert Map.has_key?(book.relationships, :editor),
             "`include_private_relationships?: true` stopped reaching the generator"

      assert %{public?: false} =
               book.custom
               |> Map.fetch!(@namespace)
               |> get_in([:by_name, :relationships, :editor])
    end

    test "the public one beside it still is selectable" do
      assert %{"success" => true, "data" => books} =
               run(%{"action" => "list_books", "fields" => [%{"author" => ["id"]}]})

      assert is_list(books)
    end
  end

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp errors(response) do
    assert %{"success" => false, "errors" => errors} = response
    errors
  end

  defp create_author(name, email) do
    assert %{"success" => true} =
             run(%{
               "action" => "create_author",
               "input" => %{"name" => name, "email" => email},
               "fields" => ["id"]
             })
  end

  defp find_author(name) do
    assert %{"success" => true, "data" => authors} = run(%{"action" => "list_authors"})

    Enum.find(authors, &(&1["name"] == name)) || flunk("#{name} is not in the response")
  end

  # Serves `Test.Manifest`'s own decorated manifest with one resource's payload
  # rewritten, through a module that answers `persisted/2`. Nothing else
  # changes, so a difference in the response is the tamper and only the tamper.
  defp tamper(module, fun) do
    manifest = Manifest.manifest(Test.Manifest)

    resources =
      Enum.map(manifest.resources, fn
        %{module: ^module} = resource ->
          payload = resource.custom |> Map.fetch!(@namespace) |> fun.()
          %{resource | custom: Map.put(resource.custom, @namespace, payload)}

        other ->
          other
      end)

    Test.OverrideManifest.put(%{manifest: %{manifest | resources: resources}})
    Application.put_env(:ash_kotlin_multiplatform, :manifest, Test.OverrideManifest)
  end

  # `AshIntrospection.Manifest.Decorator` keys `by_name` by both the atom and
  # the string (`decorator.ex:255`), so a tamper writes both or the reader finds
  # the original under the other key.
  defp tamper_by_name(payload, kind, name, fun) do
    tampered = payload |> get_in([:by_name, kind, name]) |> fun.()

    update_in(payload, [:by_name, kind], fn entities ->
      entities |> Map.put(name, tampered) |> Map.put(to_string(name), tampered)
    end)
  end
end
