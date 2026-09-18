# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Book do
  @moduledoc """
  The far side of `Author.books`, so a nested field request has somewhere to go.
  """
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshKotlinMultiplatform.Resource]

  # Shared by `book_note` and `book_notes` so the single and the list return
  # the same three members, one per default the runner gives a union member.
  @union_members [
    note: [type: AshKotlinMultiplatform.Test.UnionNote],
    tally: [
      type: :map,
      constraints: [fields: [book_count: [type: :integer], top_title: [type: :string]]]
    ],
    headline: [type: :string]
  ]

  ets do
    private? true
  end

  kotlin_multiplatform do
    type_name("Book")
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
      allow_nil? false
    end

    # The embedded routes #84 measured, one per fixture. Only `meta` was found
    # by the one-level attribute walk this library used before it read the
    # manifest.
    attribute :meta, AshKotlinMultiplatform.Test.BookMeta, public?: true
    attribute :private_meta, AshKotlinMultiplatform.Test.PrivateMeta, public?: false

    attribute :extra, :union do
      public? true
      constraints types: [note: [type: AshKotlinMultiplatform.Test.UnionNote]]
    end
  end

  relationships do
    belongs_to :author, AshKotlinMultiplatform.Test.Author do
      public? true
      attribute_public? true
    end

    # Private on purpose. `Ash.Info.Manifest.Generator.generate/1` defaults
    # `:include_private_relationships?` to false, so this relationship is in no
    # manifest built with the defaults — which is how `ash_introspection`
    # shipped a `relationship/3` that answered nil where `Ash.Resource.Info`
    # answers the relationship. This is the fixture that fails if
    # `BuildManifest` ever stops passing the option.
    belongs_to :editor, AshKotlinMultiplatform.Test.Author do
      public? false
      attribute_public? false
    end
  end

  calculations do
    calculate :cover,
              AshKotlinMultiplatform.Test.Cover,
              fn records, _context -> Enum.map(records, fn _record -> nil end) end do
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    action :summarize, AshKotlinMultiplatform.Test.Summary do
      argument :opts, AshKotlinMultiplatform.Test.SummaryOpts, public?: true

      run fn input, _context ->
        label =
          case input.arguments[:opts] do
            %{label: label} -> label
            _ -> nil
          end

        {:ok, %AshKotlinMultiplatform.Test.Summary{label: label}}
      end
    end

    # A generic action returning a list of the same embedded resource, so the
    # generated signature has to name `List<Summary>` (#87).
    action :summarize_all, {:array, AshKotlinMultiplatform.Test.Summary} do
      run fn _input, _context ->
        {:ok,
         [
           %AshKotlinMultiplatform.Test.Summary{label: "One"},
           %AshKotlinMultiplatform.Test.Summary{label: "Two"}
         ]}
      end
    end

    # A generic action returning a resource other than its owner. Codegen named
    # the owner, `Book`, here before #87.
    #
    # `:struct` with `instance_of` rather than the bare `Author` module: naming
    # `Author` as the return type failed to compile `Book` with "Author is not
    # a valid type". At runtime `FieldSelector.select_fields/5` sends both forms
    # to `select_resource_fields/4`.
    action :sample_author, :struct do
      constraints instance_of: AshKotlinMultiplatform.Test.Author

      run fn _input, _context ->
        {:ok,
         %AshKotlinMultiplatform.Test.Author{
           id: "00000000-0000-0000-0000-000000000001",
           name: "Sample",
           email: "sample@example.com"
         }}
      end
    end

    # A generic action returning a map that declares its fields. A request
    # with no `fields` gets those field names; before #88 it got Book's
    # attribute names, every value nil.
    action :tally, :map do
      constraints fields: [
                    book_count: [type: :integer],
                    top_title: [type: :string]
                  ]

      run fn _input, _context -> {:ok, %{book_count: 2, top_title: "Kindred"}} end
    end

    # A generic action returning a map with no declared fields. The runner
    # sends it as it is, with or without `fields` (#88 left this unchanged).
    action :raw_stats, :map do
      run fn _input, _context -> {:ok, %{"shelf_count" => 3}} end
    end

    # Generic actions returning each typed container other than a map, alone
    # and in a list. A request with no `fields` gets the declared field names.
    # Before #95 each sent Book's attribute names, every value nil, because the
    # runner's default only recognised `:map`.
    #
    # A `:struct` with `fields` and no `instance_of`: a typed map by another
    # name. The run function returns a plain map, which the struct type reads.
    action :book_stats, :struct do
      constraints fields: [
                    book_count: [type: :integer],
                    top_title: [type: :string]
                  ]

      run fn _input, _context -> {:ok, %{book_count: 2, top_title: "Kindred"}} end
    end

    action :book_stats_all, {:array, :struct} do
      constraints items: [
                    fields: [
                      book_count: [type: :integer],
                      top_title: [type: :string]
                    ]
                  ]

      run fn _input, _context ->
        {:ok, [%{book_count: 1, top_title: "A"}, %{book_count: 2, top_title: "B"}]}
      end
    end

    # A `:tuple` names its elements by position, so its template carries each
    # field's index rather than a key (`FieldSelector.select_tuple_fields/4`).
    action :book_pair, :tuple do
      constraints fields: [
                    book_count: [type: :integer],
                    top_title: [type: :string]
                  ]

      run fn _input, _context -> {:ok, {2, "Kindred"}} end
    end

    action :book_pairs, {:array, :tuple} do
      constraints items: [
                    fields: [
                      book_count: [type: :integer],
                      top_title: [type: :string]
                    ]
                  ]

      run fn _input, _context -> {:ok, [{1, "A"}, {2, "B"}]} end
    end

    action :book_options, :keyword do
      constraints fields: [
                    book_count: [type: :integer],
                    top_title: [type: :string]
                  ]

      run fn _input, _context -> {:ok, [book_count: 2, top_title: "Kindred"]} end
    end

    action :book_options_all, {:array, :keyword} do
      constraints items: [
                    fields: [
                      book_count: [type: :integer],
                      top_title: [type: :string]
                    ]
                  ]

      run fn _input, _context ->
        {:ok, [[book_count: 1, top_title: "A"], [book_count: 2, top_title: "B"]]}
      end
    end

    # A generic action returning a union, alone and in a list. Which member is
    # active is decided at result time by `%Ash.Union{type:}`, not by the
    # declaration, so the three members cover the three defaults this library
    # gives: an embedded resource gets its public attributes, a typed map its
    # declared fields, a scalar its value (#96).
    #
    # `member` picks the active one, so one action measures all three without
    # the declaration changing.
    action :book_note, :union do
      constraints types: @union_members

      argument :member, :string, public?: true, default: "note"

      run fn input, _context -> {:ok, union_member(input.arguments[:member])} end
    end

    action :book_notes, {:array, :union} do
      constraints items: [types: @union_members]

      run fn _input, _context ->
        {:ok, Enum.map(["note", "tally", "headline"], &union_member/1)}
      end
    end

    create :create do
      primary? true
      # `extra` is accepted so a test can store a union and read it back
      # through `list_books`, which is the read half of ash_introspection #84.
      accept [:title, :author_id, :extra]
    end
  end

  # Built as `%Ash.Union{}` rather than a bare value: it is the `type:` field
  # that names the active member at result time, and that is what
  # `ResultProcessor.extract_union_value/4` reads.
  defp union_member("note"),
    do: %Ash.Union{type: :note, value: %AshKotlinMultiplatform.Test.UnionNote{label: "Noted"}}

  defp union_member("tally"),
    do: %Ash.Union{type: :tally, value: %{book_count: 2, top_title: "Kindred"}}

  defp union_member("headline"), do: %Ash.Union{type: :headline, value: "Front page"}
end
