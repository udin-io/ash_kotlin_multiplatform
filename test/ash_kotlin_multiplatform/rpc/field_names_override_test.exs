# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.FieldNamesOverrideTest do
  @moduledoc """
  A `field_names` override must reach the wire AND the generated Kotlin.

  Before #71 neither side read it. `ValueFormatter.format_resource/4` is the
  only caller of the `format_field_for_client` callback that consults the
  option, and nothing called `ValueFormatter`; `ResourceSchemas.format_field_name/1`
  camelized the attribute name and never looked the option up. The two agreed
  by both ignoring it, so the DSL option was documented and dead.

  Fixing only the runner would have been worse than leaving it: the server would
  send `addressLine1` while the Kotlin class still declared `addressLine_1`, and
  kotlinx-serialization would read `null`. That is the #24 and #51 failure
  shape exactly — code that compiles and then decodes nothing — so both halves
  are asserted here as one pair.

  The key type matters as much as the key text. `Info.kotlin_field_names/1`
  returns the DSL's keyword list, whose values are atoms, while every other key
  in a payload is a string from `FieldFormatter.format_field_name/2`. An atom
  key encodes to the right JSON but fails `Map.get(data, "addressLine1")`, so
  the payload would be correct on the wire and wrong in Elixir. The assertion
  below names the type deliberately.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Resource.Info
  alias AshKotlinMultiplatform.Rpc.Runner
  alias AshKotlinMultiplatform.Test.Author

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp create_author do
    assert %{"success" => true, "data" => author} =
             run(%{
               "action" => "create_author",
               "input" => %{
                 "name" => "Ursula Le Guin",
                 "email" => "ursula-#{System.unique_integer([:positive])}@example.com",
                 "addressLine1" => "10 Downing Street"
               },
               "fields" => ["id", "name", "addressLine1"]
             })

    author
  end

  defp author_class do
    {resource_classes, _, _, _} = ResourceSchemas.generate_all_schemas([Author])
    resource_classes
  end

  describe "the server side" do
    test "the response carries the overridden name, not the attribute name" do
      author = create_author()

      assert author["addressLine1"] == "10 Downing Street"
      refute Map.has_key?(author, "addressLine1" |> String.to_atom())
      refute Map.has_key?(author, "address_line_1")
    end

    test "the overridden key is a string, like every other key in the payload" do
      author = create_author()

      for key <- Map.keys(author) do
        assert is_binary(key), "expected every payload key to be a String, got #{inspect(key)}"
      end
    end

    test "the whole response still encodes" do
      json = create_author() |> Phoenix.json_library().encode!()

      assert json =~ ~s("addressLine1":"10 Downing Street")
    end

    test "an input sent under the overridden name reaches the attribute" do
      author = create_author()

      assert %{"success" => true, "data" => %{"addressLine1" => "10 Downing Street"}} =
               run(%{
                 "action" => "get_author",
                 "input" => %{"id" => author["id"]},
                 "fields" => ["addressLine1"]
               })
    end
  end

  describe "the generated Kotlin" do
    test "declares the property under the overridden name" do
      assert author_class() =~ "val addressLine1:"
    end

    test "never declares the raw attribute name" do
      refute author_class() =~ "addressLine_1"
      refute author_class() =~ "addressLine1_"
    end

    test "needs no @SerialName, because the property name is the wire key" do
      refute author_class() =~ ~S|@SerialName("address_line_1")|
    end
  end

  describe "Info.client_field_name/3" do
    test "returns the override as a string" do
      assert Info.client_field_name(Author, :address_line_1, :camel_case) == "addressLine1"
    end

    test "falls back to the formatter when no override exists" do
      assert Info.client_field_name(Author, :book_count, :camel_case) == "bookCount"
      assert Info.client_field_name(Author, :book_count, :snake_case) == "book_count"
    end

    test "an override is not re-formatted by the output formatter" do
      assert Info.client_field_name(Author, :address_line_1, :snake_case) == "addressLine1"
    end
  end
end
