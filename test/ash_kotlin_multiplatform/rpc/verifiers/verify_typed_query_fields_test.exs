# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

# Resources used by the relationship checks live at the top level: a resource
# defined inside a test body is not fully compiled when the domain that points
# at it is verified, so `Ash.Resource.Info.public_relationships/1` returns
# nothing and the check silently passes (see verify_public_actions_test.exs).

defmodule AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshKotlinMultiplatform.Resource]

  ets do
    private?(true)
  end

  kotlin_multiplatform do
    type_name("VtqfTarget")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      public?(true)
    end

    attribute :internal_secret, :string do
      public?(false)
    end
  end

  actions do
    defaults([:read])
  end
end

defmodule AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshKotlinMultiplatform.Resource]

  ets do
    private?(true)
  end

  kotlin_multiplatform do
    type_name("VtqfSource")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      public?(true)
    end

    attribute :internal_note, :string do
      public?(false)
    end
  end

  relationships do
    belongs_to :public_target, AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target do
      public?(true)
      attribute_writable?(true)
    end

    belongs_to :private_target, AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target do
      public?(false)
      attribute_writable?(true)
    end
  end

  calculations do
    calculate :ranking_score, :integer, expr(1) do
      public?(true)
      field?(false)
    end
  end

  actions do
    defaults([:read])
  end
end

defmodule AshKotlinMultiplatform.Rpc.Verifiers.VerifyTypedQueryFieldsTest do
  @moduledoc """
  A `typed_query` field must resolve to a public attribute, relationship or
  `field?: true` calculation, walking into nested relationship selections —
  or `mix compile` fails naming it.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  test "rejects a typed_query naming a field?: false calculation" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyTypedQueryFields.FieldFalseDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source)
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target)
          end

          kotlin_rpc do
            resource AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
              typed_query :probe_query, :read do
                fields([:ranking_score])
                kotlin_result_type_name("ProbeQueryResult")
                kotlin_fields_const_name("PROBE_QUERY_FIELDS")
              end
            end
          end
        end
      end

    assert error.message =~ "ranking_score"
    assert error.message =~ "field?: false"
  end

  test "rejects a typed_query naming a field that is not on the resource" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyTypedQueryFields.UnknownFieldDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source)
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target)
          end

          kotlin_rpc do
            resource AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
              typed_query :probe_query, :read do
                fields([:totally_not_a_field])
                kotlin_result_type_name("ProbeQueryResult")
                kotlin_fields_const_name("PROBE_QUERY_FIELDS")
              end
            end
          end
        end
      end

    assert error.message =~ "totally_not_a_field"
  end

  test "rejects a typed_query naming a private attribute" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyTypedQueryFields.PrivateAttrDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source)
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target)
          end

          kotlin_rpc do
            resource AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
              typed_query :probe_query, :read do
                fields([:internal_note])
                kotlin_result_type_name("ProbeQueryResult")
                kotlin_fields_const_name("PROBE_QUERY_FIELDS")
              end
            end
          end
        end
      end

    assert error.message =~ "internal_note"
  end

  test "rejects a typed_query naming a private relationship" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyTypedQueryFields.PrivateRelDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source)
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target)
          end

          kotlin_rpc do
            resource AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
              typed_query :probe_query, :read do
                fields(private_target: [:id])
                kotlin_result_type_name("ProbeQueryResult")
                kotlin_fields_const_name("PROBE_QUERY_FIELDS")
              end
            end
          end
        end
      end

    assert error.message =~ "private_target"
  end

  test "rejects a typed_query naming a nested field private on the destination resource" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyTypedQueryFields.NestedPrivateDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source)
            resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target)
          end

          kotlin_rpc do
            resource AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
              typed_query :probe_query, :read do
                fields(public_target: [:internal_secret])
                kotlin_result_type_name("ProbeQueryResult")
                kotlin_fields_const_name("PROBE_QUERY_FIELDS")
              end
            end
          end
        end
      end

    assert error.message =~ "public_target.internal_secret"
  end

  test "accepts public attributes, a nested public relationship field, and a field?: true calculation" do
    refute_dsl_errors do
      defmodule Elixir.AshKotlinMultiplatform.Test.VerifyTypedQueryFields.HappyPathDomain do
        @moduledoc false
        use Ash.Domain,
          extensions: [AshKotlinMultiplatform.Rpc],
          validate_config_inclusion?: false

        resources do
          resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source)
          resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target)
        end

        kotlin_rpc do
          resource AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
            typed_query :probe_query, :read do
              fields([:name, public_target: [:id, :title]])
              kotlin_result_type_name("ProbeQueryResult")
              kotlin_fields_const_name("PROBE_QUERY_FIELDS")
            end
          end
        end
      end
    end
  end

  test "accepts string field names" do
    refute_dsl_errors do
      defmodule Elixir.AshKotlinMultiplatform.Test.VerifyTypedQueryFields.StringFieldsDomain do
        @moduledoc false
        use Ash.Domain,
          extensions: [AshKotlinMultiplatform.Rpc],
          validate_config_inclusion?: false

        resources do
          resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source)
          resource(AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Target)
        end

        kotlin_rpc do
          resource AshKotlinMultiplatform.Test.VerifyTypedQueryFields.Source do
            typed_query :probe_query, :read do
              fields(["name"])
              kotlin_result_type_name("ProbeQueryResult")
              kotlin_fields_const_name("PROBE_QUERY_FIELDS")
            end
          end
        end
      end
    end
  end
end
