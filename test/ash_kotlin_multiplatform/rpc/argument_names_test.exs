# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.ArgumentNamesTest do
  @moduledoc """
  An `argument_names` override must reach the generated Kotlin AND the server.

  `Author.sign_up` takes `anonymous?`, which is not a Kotlin identifier, mapped
  to `anonymous`. Before #23 neither side read the option: the generator
  emitted `val anonymous?: Boolean`, which does not compile, and the server
  answered `NoSuchInput` for `anonymous`.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Codegen.TypeGenerators.InputTypes
  alias AshKotlinMultiplatform.Rpc.Runner
  alias AshKotlinMultiplatform.Test.Author

  defp sign_up(input) do
    Runner.run_action(:ash_kotlin_multiplatform, %{
      "action" => "sign_up_author",
      "input" => Map.put(input, "name", "Ursula Le Guin"),
      "fields" => ["name"]
    })
  end

  defp validate_sign_up(input) do
    Runner.validate_action(:ash_kotlin_multiplatform, %{
      "action" => "sign_up_author",
      "input" => Map.put(input, "name", "Ursula Le Guin")
    })
  end

  defp input_class,
    do: InputTypes.generate_input_type(Author, %{name: :sign_up_author, action: :sign_up})

  describe "the generated Kotlin" do
    test "declares the renamed argument under its override" do
      assert input_class() =~ "    val anonymous: Boolean,\n"
    end

    test "never declares the raw argument name" do
      refute input_class() =~ "anonymous?"
    end

    test "an unmapped argument keeps its raw name on the wire" do
      assert input_class() =~ ~s|@SerialName("pen_name")\n    val penName: String? = null|
    end
  end

  describe "the server" do
    test "run_action takes the argument under its override" do
      assert %{"success" => true, "data" => %{"name" => "Anonymous"}} =
               sign_up(%{"anonymous" => true})
    end

    test "validate_action takes the argument under its override" do
      assert %{"success" => true, "valid" => true} = validate_sign_up(%{"anonymous" => true})
    end

    test "still takes the raw Elixir name, so a client built before the rename works" do
      assert %{"success" => true, "data" => %{"name" => "Anonymous"}} =
               sign_up(%{"anonymous?" => true})
    end

    test "takes the override's value when a request carries both names" do
      assert %{"success" => true, "data" => %{"name" => "Anonymous"}} =
               sign_up(%{"anonymous" => true, "anonymous?" => false})

      assert %{"success" => true, "data" => %{"name" => "Ursula Le Guin"}} =
               sign_up(%{"anonymous?" => true, "anonymous" => false})
    end

    test "takes an unmapped argument under its raw name" do
      assert %{"success" => true} = sign_up(%{"anonymous" => false, "pen_name" => "Tiptree"})
    end
  end
end
