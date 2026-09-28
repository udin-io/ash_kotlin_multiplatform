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
end
