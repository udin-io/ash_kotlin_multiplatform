# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RunnerErrorRedactionTest do
  @moduledoc """
  What a Kotlin client receives when an action fails (#28).

  Each test asserts on the JSON the controller would send, so a secret that
  survives anywhere in the payload fails it: in `message`, `vars`, `details`
  or a key nobody thought to check. The leak check comes first, so a test
  that fails names the leak rather than a changed `type`.

  Synchronous, because tests here write `config :ash, :policies` and repoint
  `config :ash_kotlin_multiplatform, :manifest`.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshKotlinMultiplatform.Rpc.Runner

  describe "a read a policy refuses" do
    test "sends forbidden, with no stack frame and no module name" do
      response = run(%{"action" => "list_refused_faults", "fields" => ["id"]})

      json = Jason.encode!(response)
      refute json =~ ".ex:"
      refute json =~ "AshKotlinMultiplatform"

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "forbidden"
      assert error["message"] == "forbidden"
    end

    test "sends no actor when Ash policy breakdowns are on" do
      previous = Application.get_env(:ash, :policies)
      Application.put_env(:ash, :policies, show_policy_breakdowns?: true)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:ash, :policies, previous),
          else: Application.delete_env(:ash, :policies)
      end)

      actor = %{id: 7, role: :admin, email: "ceo@corp.example"}
      response = run(%{"action" => "list_refused_faults", "fields" => ["id"]}, actor: actor)

      refute Jason.encode!(response) =~ "ceo@corp.example"
      assert %{"success" => false, "errors" => [%{"type" => "forbidden"}]} = response
    end
  end

  describe "an action that returns an error" do
    test "a string becomes unknown_error, and the string stays on the server" do
      {response, log} = with_log(fn -> run(%{"action" => "fault_return_string"}) end)

      refute Jason.encode!(response) =~ "10.0.0.5"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "unknown_error"
      assert error["message"] == "Something went wrong"
      assert log =~ "10.0.0.5"
    end

    test "a term becomes unknown_error, and its contents stay on the server" do
      {response, log} = with_log(fn -> run(%{"action" => "fault_return_term"}) end)

      refute Jason.encode!(response) =~ "sk_live_123"
      assert %{"success" => false, "errors" => [%{"type" => "unknown_error"}]} = response
      assert log =~ "sk_live_123"
    end
  end

  describe "an action that raises" do
    test "returns a failed result, and the exception stays on the server" do
      {response, log} = with_log(fn -> run(%{"action" => "fault_raise"}) end)

      refute Jason.encode!(response) =~ "hunter2"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "unknown_error"
      assert error["message"] == "Something went wrong"
      assert log =~ "hunter2"
    end

    test "returns a failed result from validate_action/3 too" do
      {response, log} =
        with_log(fn ->
          Runner.validate_action(:ash_kotlin_multiplatform, %{
            "action" => "create_fault_raising",
            "input" => %{"title" => "Fine title"}
          })
        end)

      refute Jason.encode!(response) =~ "hunter2"
      assert %{"success" => false, "errors" => [%{"type" => "unknown_error"}]} = response
      assert log =~ "hunter2"
    end
  end

  describe "an attribute that fails a constraint" do
    test "names the field, in fields and in field, with no bread crumbs" do
      response = run(%{"action" => "create_fault", "input" => %{"title" => "ab"}})

      refute Jason.encode!(response) =~ "Bread Crumbs"
      assert %{"success" => false, "errors" => [error]} = response
      assert_title_too_short(error)
    end

    test "names the field the same way from validate_action/3" do
      response =
        Runner.validate_action(:ash_kotlin_multiplatform, %{
          "action" => "create_fault",
          "input" => %{"title" => "ab"}
        })

      refute Jason.encode!(response) =~ "Bread Crumbs"
      assert %{"success" => true, "valid" => false, "errors" => [error]} = response
      assert_title_too_short(error)
    end
  end

  describe "a required attribute left out" do
    test "names the field, with no bread crumbs" do
      response = run(%{"action" => "create_fault", "input" => %{}})

      refute Jason.encode!(response) =~ "Bread Crumbs"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "required"
      assert error["message"] == "attribute title is required"
      assert error["field"] == "title"
    end
  end

  # Decision 4 on #123: ash_introspection 0.6.0 words none of these, so the
  # client gets internal_error until the core names the key.
  describe "a request naming an input key that does not exist" do
    test "gets internal_error, with no module name, and the log keeps the key" do
      {response, log} =
        with_log(fn ->
          run(%{"action" => "create_fault", "input" => %{"title" => "Fine", "zzqq" => 1}})
        end)

      refute Jason.encode!(response) =~ "AshKotlinMultiplatform"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "internal_error"
      assert error["message"] == "Something went wrong. Unique error id: #{error["errorId"]}"
      assert log =~ "zzqq"
    end
  end

  describe "a generic action returning a forbidden field" do
    test "sends null, and never the hidden value" do
      response = run(%{"action" => "fault_hidden_value"})

      refute Jason.encode!(response) =~ "s3cret-original"
      assert %{"success" => true, "data" => %{"hidden" => nil}} = response
    end
  end

  defp assert_title_too_short(error) do
    assert error["type"] == "invalid_attribute"
    assert error["shortMessage"] == "Invalid attribute"
    assert error["message"] == "length must be greater than or equal to 3"
    assert error["vars"]["min"] == 3
    assert error["fields"] == ["title"]
    assert error["field"] == "title"
  end

  defp run(params, opts \\ []),
    do: Runner.run_action(:ash_kotlin_multiplatform, params, opts)
end
