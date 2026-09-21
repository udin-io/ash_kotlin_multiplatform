# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

# Defined Zulu, Mike, Alpha on purpose. A module's atom is created when the
# compiler reads its `defmodule`, so these three sit in the atom table in
# reverse alphabetical order — which is the condition that makes a map-ordered
# section emit them in the wrong order. Their names are the whole fixture; the
# attributes and the read action are the minimum the generators need.
#
# Named by no domain, so nothing they declare reaches the compile or round-trip
# gate fixtures.
defmodule AshKotlinMultiplatform.Test.OutputOrder.Zulu do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Zulu")
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.OutputOrder.Mike do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Mike")
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.OutputOrder.Alpha do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Alpha")
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Rpc.Codegen.StableOutputOrderTest do
  @moduledoc """
  Two generated sections took their order from map iteration, so the same commit
  emitted their blocks in a different order on every build (#43, #17).

  Erlang orders atoms two different ways. `Enum.sort/1` uses the documented term
  order, which compares atoms codepoint by codepoint. Map iteration uses the
  VM's internal order, which compares them by atom table index — creation order.
  So a map keyed by resource module iterates in the order the VM happened to
  load those modules, and that shifts with compile order:

      iex> Enum.sort([:"Elixir.ZZZ", :"Elixir.AAA"])
      [AAA, ZZZ]
      iex> Map.keys(%{:"Elixir.ZZZ" => 1, :"Elixir.AAA" => 2})
      [ZZZ, AAA]

  Measured on `main` at 33fcfa8: four `mix compile --force` builds of this test
  domain emitted the `object …Rpc` wrappers in four different orders, with four
  different md5s and byte-identical bodies.

  ## Two things that do not work as tests

  **A snapshot of today's sequence.** It passes again the moment the order
  moves, which is how this shipped twice. Every assertion here compares against
  a list the test computes with `Enum.sort/1`.

  **Permuting the input list.** `Enum.group_by/2` builds the same map whatever
  order its input arrives in, and map iteration reads the atom table, not the
  insertion order — so the buggy code returns byte-identical output for every
  permutation. Issue #17's test plan proposes exactly that check; it is green on
  the defect. What separates the two is whether the emitted order is *sorted*,
  and the modules above force the case where sorted and atom-table order differ.
  """
  # Not async: swaps :ash_domains, which is global.
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Codegen.TypedQueries
  alias AshKotlinMultiplatform.Rpc.Codegen
  alias AshKotlinMultiplatform.Rpc.Codegen.RpcConfigCollector
  alias AshKotlinMultiplatform.Rpc.RpcAction
  alias AshKotlinMultiplatform.Rpc.TypedQuery
  alias AshKotlinMultiplatform.Test
  alias AshKotlinMultiplatform.Test.OutputOrder

  @reverse_of_alphabetical [OutputOrder.Zulu, OutputOrder.Mike, OutputOrder.Alpha]

  setup do
    previous = Application.get_env(:ash_kotlin_multiplatform, :ash_domains)

    Application.put_env(:ash_kotlin_multiplatform, :ash_domains, [Test.Domain])

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:ash_kotlin_multiplatform, :ash_domains)
        value -> Application.put_env(:ash_kotlin_multiplatform, :ash_domains, value)
      end
    end)

    :ok
  end

  describe "the fixture modules" do
    test "iterate as a map in the reverse of their sorted order" do
      as_map = @reverse_of_alphabetical |> Map.new(&{&1, []}) |> Map.keys()

      assert as_map == @reverse_of_alphabetical
      assert Enum.sort(as_map) == Enum.reverse(@reverse_of_alphabetical)
    end
  end

  describe "object wrappers" do
    test "are emitted sorted by the type name the wrapper carries" do
      wrappers =
        @reverse_of_alphabetical
        |> Enum.map(&rpc_config/1)
        |> Codegen.render_object_wrappers("com.example.ash")
        |> wrapper_names()

      assert wrappers == ["Alpha", "Mike", "Zulu"]
    end

    test "are emitted sorted in the full generated file" do
      wrappers = generated_file() |> wrapper_names()

      assert wrappers == Enum.sort(wrappers)
    end

    test "are emitted once per RPC resource" do
      resources =
        :ash_kotlin_multiplatform
        |> RpcConfigCollector.get_rpc_configs()
        |> Enum.map(& &1.resource)
        |> Enum.uniq()

      assert length(generated_file() |> wrapper_names()) == length(resources)
    end
  end

  describe "typed query sections" do
    test "are emitted sorted by the resource name the header carries" do
      section =
        @reverse_of_alphabetical
        |> Enum.map(&typed_query/1)
        |> TypedQueries.generate_typed_queries_section(@reverse_of_alphabetical)

      assert section_names(section) == ["Alpha", "Mike", "Zulu"]
    end
  end

  defp generated_file do
    {:ok, code} = Codegen.generate_kotlin_code(:ash_kotlin_multiplatform, [])
    code
  end

  defp wrapper_names(code) do
    ~r/^object (\w+)Rpc \{$/m |> Regex.scan(code) |> Enum.map(&Enum.at(&1, 1))
  end

  defp section_names(code) do
    ~r|^// (\w+) Typed Queries$|m |> Regex.scan(code) |> Enum.map(&Enum.at(&1, 1))
  end

  defp rpc_config(resource) do
    %AshKotlinMultiplatform.Rpc.Resource{
      resource: resource,
      rpc_actions: [%RpcAction{name: :list_things, action: :read}]
    }
  end

  # The shape `RpcConfigCollector.get_typed_queries/1` returns. Built by hand
  # because the test domain declares no `typed_query` — the round-trip gate has
  # no coverage for one yet, see `AshKotlinMultiplatform.Test.ScopedDomain`.
  defp typed_query(resource) do
    name = resource |> Module.split() |> List.last() |> String.downcase()

    {resource, Ash.Resource.Info.action(resource, :read),
     %TypedQuery{
       name: :"list_#{name}",
       resource: resource,
       action: :read,
       fields: ["id", "title"]
     }}
  end
end
