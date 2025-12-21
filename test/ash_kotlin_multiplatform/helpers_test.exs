# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.HelpersTest do
  use ExUnit.Case, async: true

  alias AshIntrospection.Helpers

  describe "snake_to_camel_case/1" do
    test "converts simple snake_case" do
      assert Helpers.snake_to_camel_case("hello_world") == "helloWorld"
    end

    test "handles single word" do
      assert Helpers.snake_to_camel_case("hello") == "hello"
    end

    test "handles multiple underscores" do
      assert Helpers.snake_to_camel_case("hello_world_foo_bar") == "helloWorldFooBar"
    end

    test "handles leading underscore" do
      # Leading underscores cause first segment to be capitalized
      assert Helpers.snake_to_camel_case("_private_field") == "PrivateField"
    end
  end

  describe "snake_to_pascal_case/1" do
    test "converts simple snake_case" do
      assert Helpers.snake_to_pascal_case("hello_world") == "HelloWorld"
    end

    test "handles single word" do
      assert Helpers.snake_to_pascal_case("hello") == "Hello"
    end

    test "handles atom input" do
      assert Helpers.snake_to_pascal_case(:hello_world) == "HelloWorld"
    end
  end

  describe "camel_to_snake_case/1" do
    test "converts camelCase to snake_case" do
      assert Helpers.camel_to_snake_case("helloWorld") == "hello_world"
    end

    test "handles PascalCase" do
      assert Helpers.camel_to_snake_case("HelloWorld") == "hello_world"
    end

    test "handles consecutive capitals" do
      # Consecutive capitals are lowercased together
      assert Helpers.camel_to_snake_case("XMLParser") == "xmlparser"
    end
  end
end
