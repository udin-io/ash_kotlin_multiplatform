# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

# At the top level: a resource defined inside a test body is not fully compiled
# when the domain that points at it is verified.
defmodule AshKotlinMultiplatform.Test.VerifyArgumentNames.Confirmable do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("Confirmable")
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]

    create :confirm do
      argument :confirm?, :boolean, public?: true
    end
  end
end

defmodule AshKotlinMultiplatform.Rpc.Verifiers.VerifyArgumentNamesTest do
  @moduledoc """
  An exposed action's argument becomes a Kotlin property, so an argument named
  `confirm?` with no `argument_names` override generated `val confirm?:`,
  which does not compile (#23). The domain now fails to compile instead, and
  says which override to add.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  alias AshKotlinMultiplatform.Test.VerifyArgumentNames.Confirmable

  test "rejects an unmapped ? argument on an exposed action, naming the override to add" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyArgumentNames.ExposedDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource Confirmable
          end

          kotlin_rpc do
            resource Confirmable do
              rpc_action :confirm_thing, :confirm
            end
          end
        end
      end

    assert error.message =~ "RPC action confirm_thing (action: confirm)"
    assert error.message =~ "argument confirm?"
    assert error.message =~ "argument_names confirm: [confirm?: :confirm]"
  end

  test "accepts a ? argument on an action no rpc_action exposes" do
    refute_dsl_errors do
      defmodule Elixir.AshKotlinMultiplatform.Test.VerifyArgumentNames.UnexposedDomain do
        @moduledoc false
        use Ash.Domain,
          extensions: [AshKotlinMultiplatform.Rpc],
          validate_config_inclusion?: false

        resources do
          resource Confirmable
        end

        kotlin_rpc do
          resource Confirmable do
            rpc_action :list_things, :read
          end
        end
      end
    end
  end
end
