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

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Manifest.Entrypoints
  alias AshKotlinMultiplatform.Rpc.Runner
  alias AshKotlinMultiplatform.Test

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

    for action <- ["fault_exit", "fault_throw"] do
      test "#{action}: an exit or a throw is a failed result too" do
        {response, log} = with_log(fn -> run(%{"action" => unquote(action)}) end)

        refute Jason.encode!(response) =~ "hunter2"
        assert %{"success" => false, "errors" => [%{"type" => "unknown_error"}]} = response
        assert log =~ "hunter2"
      end
    end

    test "an exit is a failed result from validate_action/3 too" do
      {response, log} =
        with_log(fn ->
          Runner.validate_action(:ash_kotlin_multiplatform, %{
            "action" => "create_fault_exiting",
            "input" => %{"title" => "Fine title"}
          })
        end)

      refute Jason.encode!(response) =~ "hunter2"
      assert %{"success" => false, "errors" => [%{"type" => "unknown_error"}]} = response
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

  describe "a resource's handle_rpc_error/2" do
    test "gets the caller's context from run_action/3" do
      {response, _log} =
        with_log(fn ->
          run(%{"action" => "fault_return_string"}, context: %{relabel_errors: "Relabelled"})
        end)

      assert %{"success" => false, "errors" => [%{"shortMessage" => "Relabelled"}]} = response
    end

    test "gets the caller's context from validate_action/3" do
      response =
        Runner.validate_action(
          :ash_kotlin_multiplatform,
          %{"action" => "create_fault", "input" => %{"title" => "ab"}},
          context: %{relabel_errors: "Relabelled"}
        )

      assert %{"valid" => false, "errors" => [%{"shortMessage" => "Relabelled"}]} = response
    end
  end

  # Decision 5 on #123: a request error passes through the same handlers.
  describe "an error in the request itself" do
    test "reaches the resource's handle_rpc_error/2" do
      response =
        run(%{"action" => "fault_return_string", "fields" => ["nope"]},
          context: %{relabel_errors: "Relabelled"}
        )

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "invalid_field_selection"
      assert error["shortMessage"] == "Relabelled"
    end

    test "reaches the handler from validate_action/3 too" do
      response =
        Runner.validate_action(
          :ash_kotlin_multiplatform,
          %{"action" => "fault_raise"},
          context: %{relabel_errors: "Relabelled"}
        )

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "unsupported"
      assert error["shortMessage"] == "Relabelled"
    end

    test "is dropped when the domain's error_handler returns nil" do
      serve_under(Test.JunkHandlerDomain, "fault_return_string")

      response =
        run(%{"action" => "fault_return_string", "fields" => ["nope"]},
          context: %{handler_returns: nil}
        )

      assert %{"success" => false, "errors" => []} = response
    end
  end

  describe "a domain with show_raised_errors? true" do
    setup do
      serve_under(Test.RaisedErrorsDomain, "fault_raise")
    end

    test "sends the exception's own message" do
      {response, _log} = with_log(fn -> run(%{"action" => "fault_raise"}) end)

      assert %{"success" => false, "errors" => [error]} = response
      assert error["message"] =~ "db password=hunter2"
    end
  end

  describe "a domain whose error_handler raises" do
    setup do
      serve_under(Test.FailingHandlerDomain, "fault_return_string")
    end

    test "fails closed: internal_error, with an id the log shares" do
      {response, log} = with_log(fn -> run(%{"action" => "fault_return_string"}) end)

      json = Jason.encode!(response)
      refute json =~ "10.0.0.5"
      refute json =~ "hunter2"

      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "internal_error"
      assert error["message"] == "Something went wrong. Unique error id: #{error["errorId"]}"
      assert log =~ error["errorId"]
      assert log =~ "10.0.0.5"
    end
  end

  describe "a domain whose error_handler returns neither a map nor nil" do
    setup do
      serve_under(Test.JunkHandlerDomain, "fault_return_string")
    end

    test "a handler that drops the error cannot keep it out of the log" do
      {response, log} =
        with_log(fn ->
          run(%{"action" => "fault_return_string"}, context: %{handler_returns: nil})
        end)

      assert %{"success" => false, "errors" => []} = response
      assert log =~ "10.0.0.5"
    end

    for {label, context} <- [
          {"returns a string", quote(do: %{handler_returns: "db password=hunter2"})},
          {"returns a struct",
           quote(do: %{handler_returns: %RuntimeError{message: "db password=hunter2"}})},
          {"throws", quote(do: %{handler_throws: "db password=hunter2"})}
        ] do
      test "fails closed when it #{label}" do
        {response, log} =
          with_log(fn ->
            run(%{"action" => "fault_return_string"}, context: unquote(context))
          end)

        json = Jason.encode!(response)
        refute json =~ "hunter2"
        refute json =~ "10.0.0.5"

        assert %{"success" => false, "errors" => [error]} = response
        assert error["type"] == "internal_error"
        assert error["message"] == "Something went wrong. Unique error id: #{error["errorId"]}"
        assert log =~ error["errorId"]
      end
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

      assert length(Regex.scan(~r/\[(error|warning)\]/, log)) == 1,
             "logged more than once:\n#{log}"
    end
  end

  # Decision 6 on #123: the action ran, so the client must not read the
  # failure as "nothing happened".
  describe "an action that ran but whose result cannot be formatted" do
    test "answers result_unavailable, and the log keeps the detail" do
      {response, log} = with_log(fn -> run(%{"action" => "fault_bad_vector"}) end)

      refute Jason.encode!(response) =~ "hunter2"
      assert %{"success" => false, "errors" => [error]} = response
      assert error["type"] == "result_unavailable"
      assert error["shortMessage"] == "Result unavailable"
      assert error["message"] == "The action ran, but its result could not be sent"
      assert log =~ error["errorId"]
      assert log =~ "hunter2"
    end
  end

  describe "a generic action returning a forbidden field" do
    test "in an error's vars, never sends the hidden value" do
      {response, _log} = with_log(fn -> run(%{"action" => "fault_struct_in_vars"}) end)

      refute Jason.encode!(response) =~ "s3cret-original"
      assert %{"success" => false, "errors" => [%{"type" => "invalid_attribute"}]} = response
    end

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

  # `Test.OverrideManifest` serves the real lookup with one entrypoint's domain
  # swapped. The domain is the only thing that differs, so it is what the
  # response follows.
  defp serve_under(domain, rpc_action_name) do
    original = Application.fetch_env!(:ash_kotlin_multiplatform, :manifest)
    namespace = Entrypoints.namespace()

    lookup =
      Test.Manifest
      |> Manifest.rpc_action_lookup()
      |> Map.update!(rpc_action_name, fn entrypoint ->
        %{entrypoint | config: put_in(entrypoint.config, [namespace, :domain], domain)}
      end)

    Test.OverrideManifest.put(%{rpc_action_lookup: lookup})
    Application.put_env(:ash_kotlin_multiplatform, :manifest, Test.OverrideManifest)

    on_exit(fn ->
      Test.OverrideManifest.clear()
      Application.put_env(:ash_kotlin_multiplatform, :manifest, original)
    end)
  end

  defp run(params, opts \\ []),
    do: Runner.run_action(:ash_kotlin_multiplatform, params, opts)
end
