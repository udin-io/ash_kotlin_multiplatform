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

    # A list, not a map literal: these run against one shared ETS table and the
    # author checks count rows, so the order they run in is part of the fixture.
    # `sparse_fieldset` asserts on a single author and must go before the typed
    # entries add more.
    base = [
      {"populated_untyped_map", populated_untyped_map()},
      {"vector_attribute", vector_attribute()},
      {"date_fields", date_fields()},
      {"action_metadata", action_metadata()},
      {"metadata_narrowed_away", metadata_narrowed_away()},
      {"sparse_fieldset", sparse_fieldset()},
      # After `sparse_fieldset`, which reads one author and fails on two. This
      # entry creates one, so running it earlier breaks a check that has nothing
      # to do with it.
      {"field_names_override", field_names_override()},
      {"error", error()},
      {"validation_valid", validation_valid()},
      {"validation_invalid", validation_invalid()},
      {"embedded_action_result", embedded_action_result()},
      {"embedded_list_action_result", embedded_list_action_result()},
      {"other_resource_action_result", other_resource_action_result()},
      {"embedded_action_default_fields", embedded_action_default_fields()},
      {"embedded_list_action_default_fields", embedded_list_action_default_fields()},
      {"other_resource_action_default_fields", other_resource_action_default_fields()},
      {"typed_struct_action_default_fields", typed_struct_action_default_fields()},
      {"union_action_default_fields", union_action_default_fields()},
      {"union_list_action_default_fields", union_list_action_default_fields()}
    ]

    # Bound in three steps rather than piped, so the order these run in is the
    # order they are written: `sparse_fieldset` counts authors, and the typed
    # entries create three more.
    typed = typed_results()
    get_by = get_by_results(typed)

    responses = Map.new(base ++ typed ++ get_by)

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
          "note" => nil,
          # Deliberately two words. An untyped map's keys are data and are sent
          # back as written, where a typed field name would be camelCased (#71).
          # Every other key here is one word and so cannot show the difference.
          "created_by" => "ada"
        },
        "settings" => %{"notify" => true}
      }
    })
  end

  # A populated `:vector`. Until #71 this response could not be produced at all:
  # stage 4 renamed field names and never formatted a value, so `%Ash.Vector{}`
  # reached `Jason` as its packed binary and raised `Jason.EncodeError`. The
  # entry exists to prove the array on the wire decodes into the `List<Double>`
  # #30 declared, which is the other half of that pair.
  defp vector_attribute do
    call(%{
      "action" => "create_todo",
      "input" => %{"title" => "Index me", "embedding" => [0.25, -1.5, 3.0]}
    })
  end

  # A `field_names` override on both sides of one request: the client sends
  # `addressLine1` and reads `addressLine1` back, while the attribute is
  # `address_line_1` throughout the server. Both halves were dead before #71 —
  # the server ignored the option and so did the generator — so a fixture that
  # only checked the class declaration would have passed while the option did
  # nothing.
  defp field_names_override do
    call(%{
      "action" => "create_author",
      "input" => Map.put(author_input("Mapped Name"), "addressLine1", "10 Downing Street"),
      "fields" => ["id", "name", "addressLine1"]
    })
  end

  # A generic action whose argument and return are embedded resources that only
  # the manifest finds (#84). The Kotlin side encodes the `SummaryOpts` it sends
  # and decodes the `Summary` it gets back, so both generated classes meet a real
  # server. This one names its `fields`; `embedded_action_default_fields` below
  # sends none.
  defp embedded_action_result do
    call(%{
      "action" => "summarize_book",
      "input" => %{"opts" => %{"label" => "Short"}},
      "fields" => ["label"]
    })
  end

  # A generic action returning a list of embedded resources. The generated
  # function returns `RpcResult<List<Summary>>` since #87.
  defp embedded_list_action_result do
    call(%{"action" => "summarize_all", "fields" => ["label"]})
  end

  # A generic action on Book returning an Author. The generated function
  # returned `RpcResult<Book>` before #87, naming the owner.
  defp other_resource_action_result do
    call(%{"action" => "sample_author", "fields" => ["id", "name"]})
  end

  # The three generic actions above with no `fields`. Before #88 each response
  # carried Book's keys, nearly all null, and `ashRpcJson` ignores unknown keys,
  # so Kotlin decoded `Summary(label=null)` with no error. These entries carry
  # the returned type's own fields.
  defp embedded_action_default_fields do
    call(%{"action" => "summarize_book", "input" => %{"opts" => %{"label" => "Short"}}})
  end

  defp embedded_list_action_default_fields do
    call(%{"action" => "summarize_all"})
  end

  defp other_resource_action_default_fields do
    call(%{"action" => "sample_author"})
  end

  # A generic action returning a `:struct` with declared fields, no `fields`.
  # Before #95 the response carried Book's keys, all null; the generated
  # function returns `RpcResult<JsonElement>`, so Kotlin decoded that without
  # complaint.
  defp typed_struct_action_default_fields do
    call(%{"action" => "book_stats"})
  end

  # A generic action returning a union, no `fields`. Before #96 the single sent
  # `"data": null` and the list sent `"data": []`, whatever the active member
  # was, so nothing on the Kotlin side could tell a working union from a
  # missing one. Each entry now carries the active member's own fields, which
  # is what the checks in `Roundtrip.kt` assert key by key.
  #
  # `member` is `tally`, the typed-map member: it is the one whose keys are
  # camelCased on the way out, so a check on `bookCount` proves the member's
  # declared fields reached the wire and not the member's raw map.
  defp union_action_default_fields do
    call(%{"action" => "book_note", "input" => %{"member" => "tally"}})
  end

  defp union_list_action_default_fields do
    call(%{"action" => "book_notes"})
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

  # The same action as `action_metadata`, with the client narrowing the metadata
  # away. `Pipeline.add_mutation_metadata/3` then returns the bare record rather
  # than the `%{data:, metadata:}` envelope, so one generated function produces
  # two shapes and `AshMetadata<T, M>` has to read both (#22).
  defp metadata_narrowed_away do
    call(%{
      "action" => "register_event",
      "input" => %{"name" => "Launch"},
      "metadataFields" => []
    })
  end

  # One response per branch of `FunctionCore.determine_return_type/1`, so every
  # type a generated function can name is decoded from something the server
  # really sent. Ordered: the reads count the rows the creates before them left.
  defp typed_results do
    author = call(%{"action" => "create_author", "input" => author_input("Typed One")})
    call(%{"action" => "create_author", "input" => author_input("Typed Two")})
    doomed = call(%{"action" => "create_author", "input" => author_input("Doomed")})

    [
      {"typed_create", author},
      {"typed_list", call(%{"action" => "list_authors"})},
      {"typed_offset_page",
       call(%{"action" => "list_authors", "page" => %{"limit" => 2, "count" => true}})},
      {"typed_keyset_page", call(%{"action" => "keyset_authors", "page" => %{"limit" => 2}})},
      {"typed_get", call(%{"action" => "get_author", "input" => %{"id" => id(author)}})},
      {"typed_get_miss",
       call(%{
         "action" => "get_author",
         "input" => %{"id" => "00000000-0000-0000-0000-000000000000"}
       })},
      {"typed_destroy", call(%{"action" => "destroy_author", "identity" => id(doomed)})}
    ]
  end

  # The `rpc_action` options of #25. Each entry is a response the client's own
  # config class has to produce or read, and every one of these branches was
  # unreachable before the DSL declared the options — a `get?` read had no way
  # to say which record it wanted, so it ran as a list read.
  #
  # Reuses the author `typed_results/0` already created rather than creating
  # another: `typed_list` counts rows, and it runs first.
  defp get_by_results(typed) do
    {"typed_create", created} = Enum.find(typed, &match?({"typed_create", _}, &1))
    author_id = id(created)

    [
      {"get_by_hit", call(%{"action" => "fetch_author", "getBy" => %{"id" => author_id}})},
      {"get_by_null",
       call(%{"action" => "find_author", "getBy" => %{"email" => "nobody@e.com"}})},
      {"get_by_missing_field", call(%{"action" => "fetch_author"})},
      {"get_by_unexpected_field",
       call(%{"action" => "fetch_author", "getBy" => %{"id" => author_id, "email" => "x@e.com"}})},
      {"filter_refused",
       call(%{"action" => "list_books_unfiltered", "filter" => %{"title" => "Dune"}})},
      {"sort_refused", call(%{"action" => "list_books_fixed_order", "sort" => "title"})}
    ]
  end

  defp author_input(name) do
    %{"name" => name, "email" => "#{name |> String.downcase() |> String.replace(" ", ".")}@e.com"}
  end

  defp id(%{"data" => %{"id" => id}}), do: id

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
