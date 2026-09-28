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

    test "fields sent as a string are refused without echoing an Elixir term" do
      response = run(%{"action" => "list_authors", "fields" => "id"})

      refute Jason.encode!(response) =~ "fields_must_be_a_list"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "invalid_fields_type"
      assert error["message"] == "Fields parameter must be an array"
      refute Map.has_key?(error["details"] || %{}, "error")
    end

    test "fields on a primitive return name the type without its module" do
      response = run(%{"action" => "fault_return_string", "fields" => ["length"]})

      refute Jason.encode!(response) =~ "Ash.Type"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["message"] == "Cannot select fields from primitive type String"
    end
  end

  describe "a non-map page" do
    test "a string names the parameter instead of crashing" do
      response = run(%{"action" => "list_authors", "page" => "a string"})

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "invalid_pagination"
      assert error["message"] == "Invalid pagination parameter format"
      refute Map.has_key?(error, "errorId")
      refute Jason.encode!(response) =~ ".ex:"
    end

    test "a list names the parameter instead of crashing" do
      response = run(%{"action" => "list_authors", "page" => [1, 2, 3]})

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "invalid_pagination"
      assert error["message"] == "Invalid pagination parameter format"
      refute Map.has_key?(error, "errorId")
      refute Jason.encode!(response) =~ ".ex:"
    end

    test "a valid page map still paginates" do
      assert %{"success" => true} = run(%{"action" => "list_authors", "page" => %{"limit" => 1}})
    end

    test "logs nothing: a client mistake is stated once, not a server secret" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          run(%{"action" => "list_authors", "page" => "a string"})
        end)

      assert log == ""
    end
  end

  describe "a non-map input" do
    test "a string names the parameter instead of crashing, via run_action" do
      response = run(%{"action" => "create_author", "input" => "a string"})

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "invalid_input_format"
      assert error["message"] == "Input parameter must be a map"
      refute Map.has_key?(error, "errorId")
      refute Jason.encode!(response) =~ ".ex:"
    end

    test "a string names the parameter instead of crashing, via validate_action" do
      response =
        Runner.validate_action(:ash_kotlin_multiplatform, %{
          "action" => "create_author",
          "input" => "a string"
        })

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "invalid_input_format"
      assert error["message"] == "Input parameter must be a map"
      refute Map.has_key?(error, "errorId")
    end

    test "no input key at all still resolves to an empty map and runs the action" do
      assert %{"success" => false, "errors" => [error]} = run(%{"action" => "create_author"})

      assert error["type"] == "required"
      assert error["field"] == "name"
    end

    test "logs nothing: a client mistake is stated once, not a server secret" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          run(%{"action" => "create_author", "input" => "a string"})
        end)

      assert log == ""
    end
  end

  defp run(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)
end
