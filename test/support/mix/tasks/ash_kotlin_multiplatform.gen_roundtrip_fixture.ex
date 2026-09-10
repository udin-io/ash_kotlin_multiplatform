# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshKotlinMultiplatform.GenRoundtripFixture do
  @moduledoc """
  Writes real `AshKotlinMultiplatform.Rpc.Runner` responses to JSON, for the
  Kotlin round-trip gate to decode.

  The compile gate answers "does the emitted Kotlin compile?". It cannot answer
  "does the emitted Kotlin decode what this library's own server sends?", and
  that is where nine of this repository's filed defects live: #24 shipped four
  declarations that compiled and then threw or silently read `null`, and #51 and
  #54 are the same shape. `kotlinc` has no opinion about whether a
  `@SerialName` matches the key `Runner` writes.

  So this task runs the actions rather than describing them. Every entry below
  is a response `Runner` produced in this process, encoded through
  `Phoenix.json_library/0` — the same encoder
  `AshKotlinMultiplatform.Phoenix.Controller` hands the result to — so the
  bytes the fixture carries are the bytes a Kotlin client would receive.

  One response per shape the generated client has to handle. Adding a shape
  here without a matching check in `test/fixtures/kotlin_compile/roundtrip`
  proves nothing; the two are a pair.

  Lives in `test/support` for the same reason the compile-gate task does: it is
  a development gate, and `mix.exs` ships `lib` only.

  ## Usage

      MIX_ENV=test mix ash_kotlin_multiplatform.gen_roundtrip_fixture
  """

  @shortdoc "Dumps real Rpc.Runner responses for the Kotlin round-trip gate"

  use Mix.Task

  alias AshKotlinMultiplatform.Rpc.Runner

  @output "test/fixtures/kotlin_compile/roundtrip/responses.json"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    responses = %{
      "populated_untyped_map" => populated_untyped_map(),
      "date_fields" => date_fields(),
      "action_metadata" => action_metadata(),
      "sparse_fieldset" => sparse_fieldset(),
      "error" => error(),
      "validation_valid" => validation_valid(),
      "validation_invalid" => validation_invalid()
    }

    json = Phoenix.json_library().encode!(responses)

    @output |> Path.dirname() |> File.mkdir_p!()
    File.write!(@output, json)

    Mix.shell().info("Generated #{@output} (#{map_size(responses)} responses)")
  end

  # `metadata` is `:map` with no field constraints and `settings` is `:keyword`,
  # so both reach Kotlin as the untyped-map type. A populated one is the whole
  # point: #51 measured that an absent or `null` map decodes and a populated one
  # does not.
  defp populated_untyped_map do
    call(%{
      "action" => "create_todo",
      "input" => %{
        "title" => "Ship it",
        "metadata" => %{
          "source" => "import",
          "retries" => 3,
          "verified" => true,
          "note" => nil
        },
        "settings" => %{"notify" => true}
      }
    })
  end

  # Every date and time shape Event declares, so both `:datetime_library`
  # settings decode a real ISO-8601 string rather than a null.
  defp date_fields do
    call(%{
      "action" => "create_event",
      "input" => %{
        "name" => "Launch",
        "startsOn" => "2026-01-01",
        "occurredAt" => "2026-01-01T09:30:00Z",
        "reminderAts" => ["2025-12-31T09:30:00Z", "2026-01-01T08:00:00Z"]
      }
    })
  end

  # Action metadata arrives *inside* `data`, not beside it (#24). The fixture
  # carries the proof so the Kotlin side can assert where it actually landed.
  defp action_metadata do
    call(%{
      "action" => "register_event",
      "input" => %{"name" => "Launch"},
      "metadataFields" => ["registeredAt", "confirmationCode"]
    })
  end

  # A field the client did not ask for is absent from the response, not null, so
  # every generated field needs a default (#24).
  defp sparse_fieldset do
    call(%{
      "action" => "create_author",
      "input" => %{"name" => "Ursula Le Guin", "email" => "ursula@example.com"},
      "fields" => ["id"]
    })

    call(%{"action" => "list_authors", "fields" => ["name"]})
  end

  defp error, do: call(%{"action" => "no_such_action"})

  defp validation_valid do
    validate(%{"action" => "create_todo", "input" => %{"title" => "Ship it"}})
  end

  defp validation_invalid do
    validate(%{"action" => "create_todo", "input" => %{}})
  end

  defp call(params), do: Runner.run_action(:ash_kotlin_multiplatform, params)
  defp validate(params), do: Runner.validate_action(:ash_kotlin_multiplatform, params)
end
