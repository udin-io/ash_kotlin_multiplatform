# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.FilterTypesTest do
  @moduledoc """
  The base filter types (`DateFilter`, `InstantFilter`) must name whichever
  datetime library `AshKotlinMultiplatform.datetime_library/0` selects, the
  way every other emitter does. Before this fix they hardcoded
  `kotlinx.datetime.*`, so a `:java_time` consumer got a filter block that
  named a package it never imports (issue #11).
  """
  use ExUnit.Case, async: false

  alias AshKotlinMultiplatform.Codegen.FilterTypes

  defp put_datetime_library(library) do
    previous = Application.get_env(:ash_kotlin_multiplatform, :datetime_library)
    Application.put_env(:ash_kotlin_multiplatform, :datetime_library, library)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:ash_kotlin_multiplatform, :datetime_library)
        value -> Application.put_env(:ash_kotlin_multiplatform, :datetime_library, value)
      end
    end)
  end

  describe "with datetime_library: :kotlinx_datetime" do
    setup do
      put_datetime_library(:kotlinx_datetime)
      :ok
    end

    test "DateFilter names kotlinx.datetime.LocalDate" do
      kotlin = FilterTypes.generate_base_filter_types()

      assert kotlin =~ "val eq: kotlinx.datetime.LocalDate? = null"
      assert kotlin =~ "val inValues: List<kotlinx.datetime.LocalDate>? = null"
      refute kotlin =~ "java.time"
    end

    test "InstantFilter names kotlinx.datetime.Instant, annotated @Contextual" do
      kotlin = FilterTypes.generate_base_filter_types()

      assert kotlin =~ "val eq: @Contextual kotlinx.datetime.Instant? = null"
      assert kotlin =~ "val inValues: List<@Contextual kotlinx.datetime.Instant>? = null"
    end
  end

  describe "with datetime_library: :java_time" do
    setup do
      put_datetime_library(:java_time)
      :ok
    end

    test "DateFilter names java.time.LocalDate" do
      kotlin = FilterTypes.generate_base_filter_types()

      assert kotlin =~ "val eq: java.time.LocalDate? = null"
      assert kotlin =~ "val inValues: List<java.time.LocalDate>? = null"
      refute kotlin =~ "kotlinx.datetime"
    end

    test "InstantFilter names java.time.Instant, left bare (no @Contextual)" do
      kotlin = FilterTypes.generate_base_filter_types()

      assert kotlin =~ "val eq: java.time.Instant? = null"
      assert kotlin =~ "val inValues: List<java.time.Instant>? = null"
      refute kotlin =~ "@Contextual"
    end
  end
end
