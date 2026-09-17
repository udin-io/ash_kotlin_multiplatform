# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Resource.ReturnedResourceTest.AuthorNewType do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :struct,
    constraints: [instance_of: AshKotlinMultiplatform.Test.Author]
end

defmodule AshKotlinMultiplatform.Resource.ReturnedResourceTest.CountsNewType do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [fields: [count: [type: :integer]]]
end

defmodule AshKotlinMultiplatform.Resource.ReturnedResourceTest do
  @moduledoc """
  `Resource.Info.returned_type/1` and `returned_resource/1` name what a generic
  action returns (#88).

  Codegen and `Rpc.Runner` both need the answer: codegen to name the Kotlin
  class, the runner to pick the default fields for a request with none.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Resource.Info
  alias AshKotlinMultiplatform.Resource.ReturnedResourceTest.AuthorNewType
  alias AshKotlinMultiplatform.Resource.ReturnedResourceTest.CountsNewType
  alias AshKotlinMultiplatform.Test.Author
  alias AshKotlinMultiplatform.Test.Book
  alias AshKotlinMultiplatform.Test.Summary

  defp action(name), do: Ash.Resource.Info.action(Book, name)

  defp returning(returns, constraints) do
    %{action(:sample_author) | returns: returns, constraints: constraints}
  end

  describe "returned_resource/1" do
    test "a bare embedded resource" do
      assert Info.returned_resource(action(:summarize)) == Summary
    end

    test "a list of a resource" do
      assert Info.returned_resource(action(:summarize_all)) == Summary
    end

    test "a :struct whose instance_of is a resource" do
      assert Info.returned_resource(action(:sample_author)) == Author
    end

    test "a NewType over a resource, alone and in a list" do
      assert Info.returned_resource(returning(AuthorNewType, [])) == Author

      assert Info.returned_resource(returning({:array, AuthorNewType}, items: [])) ==
               Author
    end

    test "nil for a :struct whose instance_of is not a resource" do
      assert Info.returned_resource(returning(Ash.Type.Struct, instance_of: URI)) ==
               nil
    end

    test "nil for a map, a scalar and no return" do
      assert Info.returned_resource(returning(Ash.Type.Map, [])) == nil
      assert Info.returned_resource(returning(Ash.Type.String, [])) == nil
      assert Info.returned_resource(returning(nil, [])) == nil
    end

    test "nil for an action that is not generic" do
      assert Info.returned_resource(action(:read)) == nil
    end
  end

  describe "returned_type/1" do
    test "drops the list and the NewType, keeping the constraints" do
      assert {Ash.Type.Map, constraints} =
               Info.returned_type(returning({:array, CountsNewType}, items: []))

      assert constraints |> Keyword.fetch!(:fields) |> Keyword.keys() == [:count]
    end

    test "nil for an action that is not generic" do
      assert Info.returned_type(action(:read)) == nil
    end
  end
end
