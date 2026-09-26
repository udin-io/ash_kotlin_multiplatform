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
  alias AshKotlinMultiplatform.Test.Author

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
end
