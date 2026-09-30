# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.DeclarationsTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.Declarations

  describe "names/1" do
    test "finds a top-level class, interface, object and typealias" do
      fragment = """
      class Foo(val a: String)
      interface Bar
      object Baz
      typealias Qux = String
      """

      assert Enum.sort(Declarations.names(fragment)) == ["Bar", "Baz", "Foo", "Qux"]
    end

    test "allows an annotation and modifiers on the declaration line" do
      fragment = """
      @Serializable
      sealed class Status {
          @Serializable
          data class Active(val since: String) : Status()
      }
      """

      assert Declarations.names(fragment) == ["Status"]
    end

    test "skips an indented, nested declaration" do
      fragment = """
      sealed class ContentUnion {
          data class Note(val value: String) : ContentUnion()
      }
      """

      assert Declarations.names(fragment) == ["ContentUnion"]
    end

    test "skips a nested companion object" do
      fragment = """
      class PhoenixMessage(val ref: String) {
          companion object {
              fun join(topic: String) = PhoenixMessage(topic)
          }
      }
      """

      assert Declarations.names(fragment) == ["PhoenixMessage"]
    end

    test "does not track a top-level function" do
      fragment = """
      fun createHttpClient(): HttpClient {
          return HttpClient {}
      }
      """

      assert Declarations.names(fragment) == []
    end

    test "returns an empty list for a fragment with no declaration" do
      assert Declarations.names("// just a comment\nval x = 1\n") == []
    end
  end

  describe "check/1" do
    test "returns :ok when every name is declared once" do
      assert Declarations.check([
               {"resource Todo", "data class Todo(val id: String)"},
               {"resource Book", "data class Book(val id: String)"}
             ]) == :ok
    end

    test "returns an error naming the identifier and both sources" do
      result =
        Declarations.check([
          {"attribute :status on Todo (enum class)", "enum class Status { A, B }"},
          {"resource TodoStatus (data class)", "data class Status(val id: String)"}
        ])

      assert {:error, message} = result
      assert message =~ "Status"
      assert message =~ "attribute :status on Todo (enum class)"
      assert message =~ "resource TodoStatus (data class)"
    end

    test "names every clashing identifier when more than one clashes" do
      result =
        Declarations.check([
          {"a", "class Foo\nclass Bar"},
          {"b", "class Foo"},
          {"c", "class Bar"}
        ])

      assert {:error, message} = result
      assert message =~ "Foo"
      assert message =~ "Bar"
    end

    test "the same source declaring a name twice still reports it" do
      result = Declarations.check([{"built-in", "class Foo\nclass Foo"}])

      assert {:error, message} = result
      assert message =~ "Foo"
    end

    test "an empty list is ok" do
      assert Declarations.check([]) == :ok
    end
  end
end
