# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest do
  @moduledoc """
  The Spark DSL module a consumer declares so this library reads one
  compile-time `%Ash.Info.Manifest{}` instead of introspecting per request.

      defmodule MyApp.AkmManifest do
        use AshKotlinMultiplatform.Manifest, otp_app: :my_app
      end

      # config/config.exs
      config :ash_kotlin_multiplatform, manifest: MyApp.AkmManifest

  ## Why the module lives here and not in the core

  Building a manifest needs a DSL that names the client-facing actions.
  `ash_introspection` ships none — the recorded reason its issue 26 was
  declined — so the module has to sit next to `AshKotlinMultiplatform.Rpc`,
  which already names them. This is stage 3 of `ash_introspection` issue 23.

  ## Why it is app-wide rather than per domain

  One domain cannot see the others. A per-domain manifest would fight itself
  when the same resource appears in two `kotlin_rpc` blocks, and there would be
  nowhere to hang a compile-time dependency on the *other* domains — which is
  the whole point of the edges below.

  ## The compile-time edges, and why they are not optional

  `AshKotlinMultiplatform.Manifest.Transformers.BuildManifest` discovers domains
  through `Ash.Info.domains/1`. That call happens inside a transformer, so
  Elixir's dependency tracker never sees it: editing a resource recompiles the
  resource and its domain, and leaves this module — and the manifest persisted
  on it — untouched. A stale manifest raises nothing and warns nothing. It
  answers confidently and wrongly.

  `handle_opts/1` therefore injects two kinds of real dependency into the
  module body:

    * `Application.compile_env(otp_app, :ash_domains, [])`, so adding or
      removing a domain in config recompiles this module. Emitted only when
      `:domains` is not given.
    * `<Domain>.module_info(:md5)` per domain — a static remote call, which is
      a compile-time dependency, whose result is discarded. Editing a resource
      recompiles its domain, which recompiles this module.

  Ported from `ash_typescript` `8c07331`.

  > #### `:domains` is for tests {: .warning}
  >
  > Supplying `:domains` suppresses the `Application.compile_env/3` edge, so the
  > module stops noticing a domain added to `config :my_app, ash_domains:`.
  > Never write it into a production manifest module; `mix
  > ash_kotlin_multiplatform.install` never does.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshKotlinMultiplatform.Manifest.Dsl]],
    opt_schema: [
      domains: [
        type: {:or, [{:list, :atom}, nil]},
        default: nil,
        doc:
          "Test-only. Build from exactly these domains instead of walking `Ash.Info.domains(otp_app)`. Suppresses the config compile edge."
      ]
    ]

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:domains, unquote(opts[:domains])}
      unquote_splicing(
        List.wrap(
          AshKotlinMultiplatform.Manifest.config_dependency_ast(opts[:otp_app], opts[:domains])
        ) ++
          AshKotlinMultiplatform.Manifest.domain_dependency_asts(
            opts[:otp_app],
            opts[:domains]
          )
      )
    end
  end

  @doc false
  # One `<Domain>.module_info(:md5)` per domain. A static remote call is a
  # compile-time dependency, and `:md5` is the cheapest thing to ask for; the
  # result is discarded.
  #
  # Public only because `handle_opts/1`'s quote is evaluated in the consumer's
  # module, where a private function here is out of reach.
  def domain_dependency_asts(otp_app, explicit_domains) do
    domains =
      explicit_domains ||
        (otp_app && Application.get_env(otp_app, :ash_domains, [])) || []

    for domain <- domains do
      quote do
        _ = unquote(domain).module_info(:md5)
      end
    end
  end

  @doc false
  # Spark runs `handle_opts/1`'s result through `Code.eval_quoted/3`
  # (`deps/spark/lib/spark/dsl.ex`), and `Application.compile_env/3` is a macro
  # whose whole job is to register the read with the compiler — so whether the
  # registration survives evaluation is not obvious from the code. It does.
  # Measured 2026-09-11 on Elixir 1.18.4: the source record for
  # `test/support/test_manifest.ex` in
  # `_build/test/lib/ash_kotlin_multiplatform/.mix/compile.elixir` carries
  # `{:ash_kotlin_multiplatform, [:ash_domains],
  #   {:ok, [AshKotlinMultiplatform.Test.Domain]}}`.
  #
  # Note the shape when reading that file: the key is a path LIST and the value
  # is wrapped in `{:ok, _}`. Looking for a bare `{app, :ash_domains, value}`
  # finds nothing and reads as "the edge is missing" when it is present.
  #
  # Emitted only when `:domains` is absent: a module scoped to an explicit list
  # does not depend on the config, and claiming otherwise would recompile it for
  # a change it deliberately ignores.
  def config_dependency_ast(otp_app, explicit_domains) do
    if is_nil(explicit_domains) and not is_nil(otp_app) do
      quote do
        _ = Application.compile_env(unquote(otp_app), :ash_domains, [])
      end
    end
  end

  @doc """
  The manifest module named by `config :ash_kotlin_multiplatform, :manifest`.

  Raises with the config line to add when none is configured.
  """
  @spec manifest_module() :: module()
  def manifest_module do
    case Application.get_env(:ash_kotlin_multiplatform, :manifest) do
      nil ->
        raise ArgumentError, """
        No `:manifest` module configured for AshKotlinMultiplatform.

        Declare one and point the config at it:

            defmodule MyApp.AkmManifest do
              use AshKotlinMultiplatform.Manifest, otp_app: :my_app
            end

            # config/config.exs
            config :ash_kotlin_multiplatform, manifest: MyApp.AkmManifest

        `mix ash_kotlin_multiplatform.install` writes both.
        """

      module ->
        module
    end
  end

  @doc "The decorated `%Ash.Info.Manifest{}` persisted on `manifest_module`."
  @spec manifest(module()) :: Ash.Info.Manifest.t() | nil
  def manifest(manifest_module \\ manifest_module()),
    do: Spark.Dsl.Extension.get_persisted(manifest_module, :manifest)

  @doc "The manifest's entrypoints — one per `rpc_action` and one per `typed_query`."
  @spec entrypoints(module()) :: [Ash.Info.Manifest.Entrypoint.t()]
  def entrypoints(manifest_module \\ manifest_module()),
    do: manifest(manifest_module).entrypoints

  @doc """
  `%{client_facing_name => %Ash.Info.Manifest.Entrypoint{}}` for every
  `rpc_action`, keyed by the name the client sends.

  Keyed off `entrypoint.config`, not off the core decorator's `client_name` —
  see `AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest` for why.
  """
  @spec rpc_action_lookup(module()) :: %{String.t() => Ash.Info.Manifest.Entrypoint.t()}
  def rpc_action_lookup(manifest_module \\ manifest_module()),
    do: Spark.Dsl.Extension.get_persisted(manifest_module, :rpc_action_lookup)

  @doc "The same map for every `typed_query`."
  @spec typed_query_lookup(module()) :: %{String.t() => Ash.Info.Manifest.Entrypoint.t()}
  def typed_query_lookup(manifest_module \\ manifest_module()),
    do: Spark.Dsl.Extension.get_persisted(manifest_module, :typed_query_lookup)
end
