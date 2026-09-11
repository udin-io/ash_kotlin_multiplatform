# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.ClientServerContractTest do
  @moduledoc """
  The Kotlin this library emits must decode what this library's own server sends.

  Issue #24 found four places where it could not, and every one of them survived
  because both halves looked right on their own. So each test here pairs a real
  response from `Runner` with the declaration the generator emits to decode it:
  changing either side alone fails the pair.

  These assertions are the cheap half. The expensive half is
  `tmp/roundtrip` in the PR that closed #24, which hands the same responses to
  a real `kotlinx-serialization` decoder — the only thing that proves a
  declaration decodes rather than merely reads correctly.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas
  alias AshKotlinMultiplatform.Codegen.TypeMapper
  alias AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic
  alias AshKotlinMultiplatform.Rpc.Runner
  alias AshKotlinMultiplatform.Test.Author

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)
  defp validate(params), do: Runner.validate_action(:ash_kotlin_multiplatform, params)

  defp create_author(name) do
    assert %{"success" => true, "data" => author} =
             run(%{
               "action" => "create_author",
               "input" => %{"name" => name, "email" => "#{name}@example.com"},
               "fields" => ["id"]
             })

    author["id"]
  end

  describe "AshRpcError.shortMessage" do
    test "the key the server sends is the key the generated class reads" do
      assert %{"success" => false, "errors" => [error]} = run(%{"action" => "no_such_action"})
      assert error["shortMessage"] == "Action not found"

      kotlin = KotlinStatic.generate_error_types()

      assert kotlin =~ "val shortMessage: String? = null"
      refute kotlin =~ "@SerialName(\"short_message\")"
    end

    test "a field-selection error uses the same key" do
      assert %{"success" => false, "errors" => [error]} =
               run(%{"action" => "list_authors", "fields" => ["nope"]})

      assert error["shortMessage"] == "Unknown field"
    end
  end

  describe "ValidationResult" do
    test "the server sends no class discriminator, so the sealed class must not need one" do
      assert validate(%{"action" => "create_todo", "input" => %{"title" => "Ship it"}}) ==
               %{"success" => true, "valid" => true}

      kotlin = KotlinStatic.generate_validation_types()

      assert kotlin =~ "@Serializable(with = ValidationResultSerializer::class)"
      assert kotlin =~ "JsonContentPolymorphicSerializer<ValidationResult>"
      refute kotlin =~ "@SerialName(\"valid\")"
      refute kotlin =~ "@SerialName(\"invalid\")"
    end

    test "an invalid changeset is discriminated by the same valid flag" do
      assert %{"success" => true, "valid" => false, "errors" => [error]} =
               validate(%{"action" => "create_todo", "input" => %{}})

      assert error["field"] == "title"
    end
  end

  describe "sparse fieldsets" do
    test "id is omitted when it was not asked for, so its Kotlin field needs a default" do
      create_author("Ursula Le Guin")

      assert %{"success" => true, "data" => [author]} =
               run(%{"action" => "list_authors", "fields" => ["name"]})

      refute Map.has_key?(author, "id")

      assert ResourceSchemas.generate_data_class(Author, [Author]) =~ "val id: String? = null"
    end
  end

  describe "RpcResult" do
    test "declares no field for a key the server never sends" do
      create_author("Octavia Butler")

      assert %{"success" => true, "data" => _} = response = run(%{"action" => "list_authors"})
      assert Map.keys(response) |> Enum.sort() == ["data", "success"]

      refute KotlinStatic.generate_generic_result_types() =~ "val metadata"
    end

    test "action metadata arrives inside data, not beside it" do
      response =
        run(%{
          "action" => "register_event",
          "input" => %{"name" => "Launch"},
          "metadataFields" => ["registeredAt"]
        })

      assert %{"success" => true, "data" => data} = response
      refute Map.has_key?(response, "metadata")
      assert data["metadata"] == %{"registeredAt" => ~U[2026-01-01 00:00:00Z]}
    end
  end

  # ash_money is not a dependency, so no `Runner` response here can carry a
  # money value and the usual pairing is impossible. The contract comes from
  # ash_money instead: `AshMoney.Types.Money.json_schema/1` documents
  # `{amount: string, currency: string}`, with `amount` a decimal string, and
  # its `Jason.Encoder` sends exactly those two keys. These assertions hold the
  # generated class to it, and to the name the mapper emits — a field typed
  # `AshMoney` with no `AshMoney` class does not compile (#30).
  describe "AshMoney" do
    test "the mapper names a class the generator declares" do
      assert TypeMapper.get_kotlin_type_for_type(AshMoney.Types.Money) == "AshMoney"

      kotlin = KotlinStatic.generate_money_type()

      assert kotlin =~ "data class AshMoney("
      assert kotlin =~ "val amount: String"
      assert kotlin =~ "val currency: String"
    end
  end
end
