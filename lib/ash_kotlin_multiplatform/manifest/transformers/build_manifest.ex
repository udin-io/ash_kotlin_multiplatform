# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.Transformers.BuildManifest do
  @moduledoc """
  Builds one app-wide `%Ash.Info.Manifest{}` from every domain's `kotlin_rpc`
  block and persists it, undecorated, as `:undecorated_manifest` and
  `:manifest`.

  `AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest` runs next and
  overwrites `:manifest` with the decorated result. The undecorated copy stays,
  because it is the only thing a test can compare the decoration against —
  `ash_introspection`'s risk T6 says a resource the decorator skipped reads live
  and says nothing, and the consumer is the only one who can notice.

  ## Why `include_private_relationships?: true`

  `Ash.Info.Manifest.Generator.generate/1` defaults it to `false`
  (`deps/ash/lib/ash/info/manifest/generator.ex`). `ash_introspection` shipped
  stage 1 with the default and `ResourceInfo.relationship/3` then answered `nil`
  for a private `belongs_to` where `Ash.Resource.Info` answers the
  relationship — and `ResourceFields.get_field_type_info/3` inherited it,
  because it asks `relationship/3` for the field's type. Passing `true` here is
  what keeps this library from repeating it one layer out.

  ## Why every module is forced to compile

  `AshIntrospection.Manifest.Decorator` reads each payload off a module atom the
  manifest names, and **skips** a module `Code.ensure_loaded?/1` cannot load.
  Under parallel compilation a referenced module may not be ready yet, so a skip
  is a resource silently left bare. `Code.ensure_compiled!/1` before generating
  and again over the finished manifest removes the race. Reachability drags in
  relationship destinations and embedded-resource modules that appear in no
  `kotlin_rpc` block, which is why the second pass reads the manifest rather
  than the DSL.
  """

  use Spark.Dsl.Transformer

  alias AshKotlinMultiplatform.Manifest.Entrypoints
  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: true

  @impl true
  def transform(dsl_state) do
    otp_app = Transformer.get_persisted(dsl_state, :otp_app)
    domains = Transformer.get_persisted(dsl_state, :domains) || Ash.Info.domains(otp_app)

    rpc_resources = Entrypoints.rpc_resources(domains)
    Enum.each(rpc_resources, &Code.ensure_compiled!/1)

    {:ok, manifest} =
      Ash.Info.Manifest.Generator.generate(
        otp_app: otp_app,
        action_entrypoints: Entrypoints.action_entrypoints(domains, rpc_resources),
        include_private_relationships?: true
      )

    ensure_all_modules_compiled(manifest)

    {:ok,
     dsl_state
     |> Transformer.persist(:undecorated_manifest, manifest)
     |> Transformer.persist(:manifest, manifest)}
  end

  defp ensure_all_modules_compiled(%Ash.Info.Manifest{resources: resources, types: types}) do
    Enum.each(resources, fn %Ash.Info.Manifest.Resource{module: module} ->
      if is_atom(module) and not is_nil(module), do: Code.ensure_compiled!(module)
    end)

    Enum.each(types, fn
      %Ash.Info.Manifest.Type{kind: :embedded_resource, module: module} when is_atom(module) ->
        if not is_nil(module), do: Code.ensure_compiled!(module)

      _ ->
        :ok
    end)
  end
end
