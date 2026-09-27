# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerRequestErrorTest do
  @moduledoc """
  A request the runner refuses before any action runs gets the shared core's
  wording, and the suggestion that goes with it (#28).
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Rpc.Runner

  test "an unknown action names itself and says what to check" do
    assert %{"success" => false, "errors" => [error]} = run(%{"action" => "no_such_action"})

    assert error["type"] == "action_not_found"
    assert error["message"] == "RPC action no_such_action not found"
    assert error["vars"] == %{"actionName" => "no_such_action"}

    assert error["details"]["suggestion"] ==
             "Check that the action is properly configured in your domain's rpc block"
  end

  test "a request with no action names the missing parameter" do
    assert %{"success" => false, "errors" => [error]} = run(%{})

    assert error["type"] == "missing_required_parameter"
    assert error["message"] == "Required parameter action is missing or empty"
    assert error["shortMessage"] == "Missing required parameter"
  end

  test "a destroy with no identity says how to send one" do
    assert %{"success" => false, "errors" => [error]} = run(%{"action" => "destroy_author"})

    assert error["type"] == "missing_identity"
    assert error["message"] == "Identity is required. Provide the id value directly."
    assert error["path"] == ["identity"]
  end

  test "a destroy with an identity naming no key lists what was sent and what is expected" do
    assert %{"success" => false, "errors" => [error]} =
             run(%{"action" => "destroy_author", "identity" => %{"nope" => "x"}})

    assert error["type"] == "invalid_identity"

    assert error["message"] ==
             "Identity fields do not match any configured identity. Provided: [nope], expected: [id]"
  end

  describe "a field selection the resource cannot answer" do
    test "an unknown field names the Kotlin type, not the Elixir module" do
      response = run(%{"action" => "list_authors", "fields" => ["nope"]})

      refute Jason.encode!(response) =~ "AshKotlinMultiplatform"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "unknown_field"
      assert error["message"] == "Unknown field nope for resource Author"
      assert error["vars"]["resource"] == "Author"
    end

    test "fields on a primitive return name the type without its module" do
      response = run(%{"action" => "fault_return_string", "fields" => ["length"]})

      refute Jason.encode!(response) =~ "Ash.Type"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["message"] == "Cannot select fields from primitive type String"
    end
  end

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)
end
