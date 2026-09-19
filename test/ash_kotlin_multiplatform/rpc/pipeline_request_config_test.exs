# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.PipelineRequestConfigTest do
  @moduledoc """
  Two config builders, and the split between them is load-bearing.

  `request_config/0` names the manifest so the request path reads it.
  `build_config/0` must not, because
  `AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest` calls it to
  build the config it decorates the manifest WITH, while the manifest module is
  still compiling (`decorate_manifest.ex:66`). A `:manifest` key there would
  ask the module being compiled for its own persisted state.

  The test for the second half is the suite itself: this repo's own manifest
  modules compile, and `mix test` would not reach a single test if they did
  not. What is asserted here is that the key is absent, so the next person
  merging the two builders fails a test instead of a build.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Rpc.Pipeline
  alias AshKotlinMultiplatform.Test

  describe "build_config/0" do
    test "names no manifest" do
      refute Map.has_key?(Pipeline.build_config(), :manifest)
      refute Map.has_key?(Pipeline.build_config(), :manifest_namespace)
    end
  end

  describe "request_config/0" do
    test "carries the manifest the config names" do
      assert Pipeline.request_config().manifest == Manifest.manifest(Test.Manifest)
    end

    test "carries the namespace the decoration was written under" do
      assert Pipeline.request_config().manifest_namespace == :ash_kotlin_multiplatform
    end

    test "is otherwise build_config/0" do
      assert Map.drop(Pipeline.request_config(), [:manifest, :manifest_namespace]) ==
               Pipeline.build_config()
    end
  end

  describe "request_config/1" do
    test "takes not_found_error? from the rpc_action" do
      assert Pipeline.request_config(%{not_found_error?: false}).not_found_error? == false
      assert Pipeline.request_config(%{}).not_found_error? == true
    end

    test "is request_config/0 with that one key" do
      rpc_action = %{not_found_error?: false}

      assert Map.delete(Pipeline.request_config(rpc_action), :not_found_error?) ==
               Map.delete(Pipeline.request_config(), :not_found_error?)
    end
  end

  describe "the manifest rides along bare" do
    test "not as a prepared AshIntrospection.ResourceInfo.Source" do
      assert %Ash.Info.Manifest{} = Pipeline.request_config().manifest
    end

    test "and the reader prepares it from those two keys" do
      source = AshIntrospection.ResourceInfo.source(Pipeline.request_config())

      assert %AshIntrospection.ResourceInfo.Source{} = source
      assert AshIntrospection.ResourceInfo.decoration(Test.Author, Pipeline.request_config())
    end
  end
end
