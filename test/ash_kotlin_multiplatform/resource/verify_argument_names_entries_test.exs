# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Resource.Verifiers.VerifyArgumentNamesEntriesTest do
  @moduledoc """
  `argument_names` was read by nothing before #23, so an entry naming a
  missing action or argument, or mapping to a name that is no better, was
  accepted and silently did nothing. Each now fails to compile.

  The resources are defined inside `assert_dsl_error`: a resource defined at
  the top of a file reports a verifier error as a compile warning, which no
  test sees.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  test "rejects an argument_names entry that names an action that does not exist" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyFieldNamesArguments.UnknownAction do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("UnknownAction")
            argument_names(confirmm: [confirm?: :confirmed])
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          actions do
            defaults [:read]

            create :confirm do
              accept [:name]
              argument :confirm?, :boolean, public?: true
              argument :note, :string, public?: true
            end
          end
        end
      end

    assert error.message =~ "argument_names"
    assert error.message =~ "confirmm"
    assert error.message =~ "no action"
  end

  test "rejects an argument_names entry that names an argument the action does not have" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyFieldNamesArguments.UnknownArgument do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("UnknownArgument")
            argument_names(confirm: [confrim?: :confirmed])
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          actions do
            defaults [:read]

            create :confirm do
              accept [:name]
              argument :confirm?, :boolean, public?: true
              argument :note, :string, public?: true
            end
          end
        end
      end

    assert error.message =~ "argument_names"
    assert error.message =~ "confrim?"
    assert error.message =~ "confirm"
  end

  test "rejects an argument_names entry that maps to a name that is itself invalid" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyFieldNamesArguments.InvalidTarget do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("InvalidTarget")
            argument_names(confirm: [confirm?: :confirmed?])
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          actions do
            defaults [:read]

            create :confirm do
              accept [:name]
              argument :confirm?, :boolean, public?: true
              argument :note, :string, public?: true
            end
          end
        end
      end

    assert error.message =~ "argument_names"
    assert error.message =~ "confirmed?"
  end

  test "rejects an argument_names entry that maps to the wire name of an accepted attribute" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyFieldNamesArguments.AttributeCollision do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("AttributeCollision")
            argument_names(confirm: [confirm?: :name])
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          actions do
            defaults [:read]

            create :confirm do
              accept [:name]
              argument :confirm?, :boolean, public?: true
              argument :note, :string, public?: true
            end
          end
        end
      end

    assert error.message =~ "argument_names"
    assert error.message =~ "name"
    assert error.message =~ "confirm?"
  end

  test "rejects an argument_names entry that maps to the wire name of another argument" do
    error =
      assert_dsl_error do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyFieldNamesArguments.ArgumentCollision do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("ArgumentCollision")
            argument_names(confirm: [confirm?: :note])
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          actions do
            defaults [:read]

            create :confirm do
              accept [:name]
              argument :confirm?, :boolean, public?: true
              argument :note, :string, public?: true
            end
          end
        end
      end

    assert error.message =~ "argument_names"
    assert error.message =~ "note"
    assert error.message =~ "confirm?"
  end

  test "accepts a ? argument with no override on the resource alone" do
    refute_dsl_errors do
      defmodule Elixir.AshKotlinMultiplatform.Test.VerifyFieldNamesArguments.Unmapped do
        @moduledoc false
        use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

        kotlin_multiplatform do
          type_name("Unmapped")
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read]

          create :confirm do
            argument :confirm?, :boolean, public?: true
          end
        end
      end
    end
  end
end
