# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.VerifyIdentities.Article do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Article")
  end

  attributes do
    uuid_primary_key :id
    attribute :slug, :string, public?: true
    attribute :draft_note, :string, public?: false
  end

  identities do
    identity :unique_slug, [:slug], pre_check_with: nil
  end

  actions do
    defaults [:read, :destroy]
    default_accept [:slug]

    update :rename do
      accept [:slug]
    end
  end
end

defmodule AshKotlinMultiplatform.Rpc.Verifiers.VerifyIdentitiesTest do
  @moduledoc """
  `identities` and `get_by` both name a lookup key, and a wrong name is only
  discoverable at runtime — as an Ash error the client author cannot trace back
  to the DSL entry that caused it. Both were unreachable before #25 exposed the
  options, so the `identities` half of this verifier could never fail.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  alias AshKotlinMultiplatform.Test.VerifyIdentities.Article

  describe "identities" do
    test "accepts an identity defined on the resource" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyIdentities.NamedIdentityDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource Article
          end

          kotlin_rpc do
            resource Article do
              rpc_action :rename_article, :rename do
                identities([:unique_slug])
              end
            end
          end
        end
      end
    end

    test "rejects an identity the resource does not define" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyIdentities.UnknownIdentityDomain do
            @moduledoc false
            use Ash.Domain,
              extensions: [AshKotlinMultiplatform.Rpc],
              validate_config_inclusion?: false

            resources do
              resource Article
            end

            kotlin_rpc do
              resource Article do
                rpc_action :rename_article, :rename do
                  identities([:unique_title])
                end
              end
            end
          end
        end

      assert error.message =~ "Identity not found"
      assert error.message =~ "unique_title"
      assert error.message =~ "unique_slug"
    end
  end

  describe "get_by" do
    test "accepts a public attribute" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyIdentities.GetByAttributeDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource Article
          end

          kotlin_rpc do
            resource Article do
              rpc_action :get_article, :read do
                get_by [:slug]
              end
            end
          end
        end
      end
    end

    # The generated GetBy data class takes its Kotlin type from the attribute,
    # so a name that is not one has no type to emit.
    test "rejects a field that is not a public attribute" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyIdentities.GetByPrivateDomain do
            @moduledoc false
            use Ash.Domain,
              extensions: [AshKotlinMultiplatform.Rpc],
              validate_config_inclusion?: false

            resources do
              resource Article
            end

            kotlin_rpc do
              resource Article do
                rpc_action :get_article, :read do
                  get_by [:draft_note]
                end
              end
            end
          end
        end

      assert error.message =~ "get_by field is not a public attribute"
      assert error.message =~ "draft_note"
      assert error.message =~ "slug"
    end
  end
end
