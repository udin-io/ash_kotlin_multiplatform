# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.CompileEdgesTest do
  @moduledoc """
  What a manifest module depends on at compile time.

  These edges are the difference between a manifest that tracks its domains and
  one that goes stale under incremental compiles with no error at all. Ported
  from `ash_typescript` `8c07331`, with the `compile_env` half moved out of
  `handle_opts/1` — see `AshKotlinMultiplatform.Manifest.config_dependency_ast/2`
  for the measurement that forced the move.

  The domain edge is asserted through `mix xref` in
  `AshKotlinMultiplatform.Manifest.CompileEdgesTest."the domain edge reaches the
  resources"`. The config edge is asserted against Elixir's own compiler
  manifest, which is the file `mix` consults to decide what to recompile.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Test

  defp emitted(otp_app, domains) do
    otp_app
    |> Manifest.domain_dependency_asts(domains)
    |> Enum.map(&Macro.to_string/1)
  end

  defp config_edge(otp_app, domains) do
    case Manifest.config_dependency_ast(otp_app, domains) do
      nil -> nil
      ast -> Macro.to_string(ast)
    end
  end

  describe "the domain edges we emit" do
    test "one module_info/1 call per configured domain" do
      # :ash_kotlin_multiplatform's own test config names exactly one domain.
      assert emitted(:ash_kotlin_multiplatform, nil) == [
               "_ = AshKotlinMultiplatform.Test.Domain.module_info(:md5)"
             ]
    end

    test "an explicit :domains list is used verbatim" do
      assert emitted(:my_app, [Test.ScopedDomain]) == [
               "_ = AshKotlinMultiplatform.Test.ScopedDomain.module_info(:md5)"
             ]
    end

    test "no otp_app and no domains emits nothing" do
      assert emitted(nil, nil) == []
    end

    test "an explicit empty domain list emits nothing" do
      assert emitted(:my_app, []) == []
    end
  end

  describe "the config edge we emit" do
    test "reads :ash_domains for the otp_app" do
      assert config_edge(:my_app, nil) ==
               "_ = Application.compile_env(:my_app, :ash_domains, [])"
    end

    # The documented cost of `:domains`: a scoped module stops noticing a domain
    # added to config. `AshKotlinMultiplatform.Manifest`'s moduledoc says so and
    # the installer never writes the option.
    test "is suppressed by an explicit :domains list" do
      assert config_edge(:my_app, [Test.ScopedDomain]) == nil
    end

    test "is suppressed when there is no otp_app to read" do
      assert config_edge(nil, nil) == nil
    end
  end

  describe "the edges reached the compiler" do
    @describetag :compile_edges

    test "the config edge is registered in Elixir's compile manifest" do
      # This is the file `mix` reads to decide what a config change
      # invalidates. An entry here is the whole mechanism; without it, adding a
      # domain to `config :my_app, ash_domains:` recompiles nothing and the
      # persisted manifest silently loses a domain.
      #
      # The shape is `{app, key_path_list, {:ok, value}}`. Asserting a bare
      # `{app, :ash_domains, value}` finds nothing and reads as a missing edge.
      assert {:ash_kotlin_multiplatform, [:ash_domains], {:ok, _}} =
               Enum.find(
                 compile_env_entries("test/support/test_manifest.ex"),
                 &match?({:ash_kotlin_multiplatform, [:ash_domains], _}, &1)
               )
    end

    test "the scoped manifest registers no config edge" do
      refute Enum.any?(
               compile_env_entries("test/support/scoped_manifest.ex"),
               &match?({_, [:ash_domains], _}, &1)
             )
    end

    test "the domain edge reaches the resources" do
      # The chain that matters is resource -> domain -> manifest module. The
      # middle link is Ash's, not ours, so it is measured rather than assumed.
      graph = xref_compile_graph()

      assert graph =~
               ~r/test\/support\/test_manifest\.ex\n(?:.*\n)*?.*test\/support\/test_domain\.ex \(compile\)/,
             "the manifest module has no compile dependency on the domain"

      assert graph =~
               ~r/test\/support\/test_domain\.ex\n(?:.*\n)*?.*test\/support\/resources\/todo\.ex \(compile\)/,
             "the domain has no compile dependency on its resources, so a resource " <>
               "edit will not recompile the manifest — inject a per-resource " <>
               "module_info/1 edge too"
    end
  end

  # The compiler manifest is a 9-tuple whose third element maps each source
  # file to a `:source` record. The compile_env reads for that file are one of
  # the record's lists. Positional rather than named, so match the entries
  # rather than the index.
  defp compile_env_entries(source_file) do
    "_build/test/lib/ash_kotlin_multiplatform/.mix/compile.elixir"
    |> File.read!()
    |> :erlang.binary_to_term()
    |> elem(2)
    |> Map.fetch!(source_file)
    |> Tuple.to_list()
    |> Enum.filter(&is_list/1)
    |> Enum.concat()
    |> Enum.filter(&match?({app, path, _} when is_atom(app) and is_list(path), &1))
  end

  defp xref_compile_graph do
    {output, 0} =
      System.cmd("mix", ["xref", "graph", "--label", "compile"],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    output
  end
end
