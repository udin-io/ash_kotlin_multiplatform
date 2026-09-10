# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.NonFieldCalculations.Report do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Report")
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  calculations do
    calculate :headline, :string, expr(title) do
      public? true
    end

    # Not a struct field: Ash keeps its value in the record's `calculations`
    # map, so the generated data class has nowhere to put it.
    calculate :ranking_score, :integer, expr(1) do
      public? true
      field? false
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.NonFieldCalculations.BadlyNamed do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("BadlyNamed")
  end

  attributes do
    uuid_primary_key :id
  end

  calculations do
    # `score_1` would be rejected by VerifyFieldNames if it were generated.
    # It is not, so the name never reaches Kotlin and must not fail the build.
    calculate :score_1, :integer, expr(1) do
      public? true
      field? false
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Codegen.NonFieldCalculationsTest do
  @moduledoc """
  A calculation declared `field?: false` is not a field on the resource struct
  — Ash stores its value in the record's `calculations` map instead. The
  generator treated every public calculation as a field, so such a calculation
  reached the Kotlin data class, the filter input and the name verifier, none
  of which can ever see a value for it.
  """
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.FilterTypes
  alias AshKotlinMultiplatform.Resource.Verifiers.VerifyFieldNames
  alias AshKotlinMultiplatform.Test.NonFieldCalculations.BadlyNamed
  alias AshKotlinMultiplatform.Test.NonFieldCalculations.Report

  test "the filter input omits a field?: false calculation" do
    kotlin = FilterTypes.generate_filter_type(Report)

    assert kotlin =~ "val headline:"
    refute kotlin =~ "rankingScore"
  end

  test "name verification ignores a field?: false calculation" do
    assert :ok = VerifyFieldNames.verify(BadlyNamed.spark_dsl_config())
  end
end
