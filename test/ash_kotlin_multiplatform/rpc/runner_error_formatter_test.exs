# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerErrorFormatterTest do
  @moduledoc """
  An error response's keys follow `output_field_formatter`, the same way a
  success response's already do (#57).

  `async: false`: every test here writes `:output_field_formatter`, which
  `Rpc.Pipeline.request_config/0` reads on every call (docs/decisions.md,
  "A test that writes application env must be `async: false`").
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Rpc.Codegen.KotlinStatic
  alias AshKotlinMultiplatform.Rpc.Runner

  setup do
    on_exit(fn -> Application.delete_env(:ash_kotlin_multiplatform, :output_field_formatter) end)
  end

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)

  defp put_formatter(formatter),
    do: Application.put_env(:ash_kotlin_multiplatform, :output_field_formatter, formatter)

  # Row 1: to_client/1, an attribute constraint failure (core error path).
  test "an attribute error under :snake_case sends short_message, not shortMessage" do
    put_formatter(:snake_case)

    assert %{"success" => false, "errors" => [error]} =
             run(%{"action" => "create_fault", "input" => %{"title" => "ab"}})

    assert error["short_message"] == "Invalid attribute"
    assert error["field"] == "title"
    assert error["fields"] == ["title"]
    assert error["vars"]["min"] == 3
    refute Map.has_key?(error, "shortMessage")
  end

  # Row 2: to_client/1, a request-reason error whose vars/details nest another
  # dictionary (request-reason path) — the bug is wider than the top level.
  test "an unexpected getBy field formats the nested vars and details keys too" do
    put_formatter(:snake_case)

    assert %{"success" => false, "errors" => [error]} =
             run(%{
               "action" => "fetch_author",
               "getBy" => %{"id" => "x", "email" => "y"}
             })

    assert error["short_message"] == "Unexpected getBy fields"
    assert error["details"]["allowed_fields"] == ["id"]
    encoded = Jason.encode!(error)
    refute encoded =~ "allowedFields"
    refute encoded =~ "shortMessage"
  end

  # Row 6 (guard): the default formatter is byte-for-byte unchanged.
  test "an attribute error under the default :camel_case still sends shortMessage" do
    assert %{"success" => false, "errors" => [error]} =
             run(%{"action" => "create_fault", "input" => %{"title" => "ab"}})

    assert error["shortMessage"] == "Invalid attribute"
    refute Map.has_key?(error, "short_message")
  end

  # Row 3: result_unavailable/2, the "must not fail" path after an action ran.
  test "a result the encoder cannot format sends error_id under :snake_case" do
    put_formatter(:snake_case)

    assert %{"success" => false, "errors" => [error]} =
             run(%{"action" => "fault_bad_vector"})

    assert Map.has_key?(error, "error_id")
    refute Map.has_key?(error, "errorId")
  end

  # Row 4: the generated Kotlin class annotates exactly the two keys that
  # change under :snake_case.
  test "generate_error_types/0 annotates short_message and error_id under :snake_case" do
    put_formatter(:snake_case)

    kotlin = KotlinStatic.generate_error_types()

    assert kotlin =~ ~r/@SerialName\("short_message"\)\s*\n\s*val shortMessage/
    assert kotlin =~ ~r/@SerialName\("error_id"\)\s*\n\s*val errorId/

    for canonical <- ["type", "message", "vars", "field", "fields", "path", "details"] do
      refute kotlin =~ "@SerialName(\"#{canonical}\")"
    end
  end

  # Row 5 (guard): every key the three probes above actually send is declared
  # by generate_error_types/0, under :snake_case.
  test "every key sent under :snake_case is covered by a declared property" do
    put_formatter(:snake_case)

    responses = [
      run(%{"action" => "create_fault", "input" => %{"title" => "ab"}}),
      run(%{"action" => "fetch_author", "getBy" => %{"id" => "x", "email" => "y"}}),
      run(%{"action" => "fault_bad_vector"})
    ]

    sent =
      for %{"errors" => errors} <- responses,
          error <- errors,
          key <- Map.keys(error),
          into: MapSet.new(),
          do: key

    declared_wire_names =
      KotlinStatic.generate_error_types()
      |> then(fn kotlin ->
        annotated =
          ~r/@SerialName\("(\w+)"\)/
          |> Regex.scan(kotlin, capture: :all_but_first)
          |> List.flatten()

        bare_properties =
          ~r/val (\w+):/
          |> Regex.scan(kotlin, capture: :all_but_first)
          |> List.flatten()

        annotated ++ bare_properties
      end)
      |> MapSet.new()

    assert MapSet.subset?(sent, declared_wire_names)
  end

  # Row 7 (guard): no @SerialName at all under the default formatter.
  test "generate_error_types/0 emits no @SerialName under the default :camel_case" do
    refute KotlinStatic.generate_error_types() =~ "@SerialName"
  end
end
