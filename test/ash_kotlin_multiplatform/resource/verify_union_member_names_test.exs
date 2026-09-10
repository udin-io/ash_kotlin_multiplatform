# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Resource.Verifiers.VerifyUnionMemberNamesTest do
  @moduledoc """
  A union attribute is the one place where a name written inside `constraints`
  becomes a Kotlin identifier. `ResourceSchemas.generate_sealed_class/1` turns
  each member name into a subclass name and each map member's field names into
  properties, so `is_valid?` emitted `data class IsValid?(` and a member field
  `ok?` emitted `val ok?:` — neither of which Kotlin will compile.

  Every other constraint name in this generator is erased: a plain `:map`
  attribute becomes an untyped map, a tuple a `List`, so their field names never
  reach Kotlin and must not be rejected.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  describe "union attributes" do
    test "rejects a union member name that is not a valid Kotlin identifier" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyUnionMemberNames.BadMember do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

            kotlin_multiplatform do
              type_name("BadMember")
            end

            attributes do
              uuid_primary_key :id

              attribute :content, :union do
                constraints types: [
                              text: [type: :string],
                              is_valid?: [type: :boolean]
                            ]

                public? true
              end
            end

            actions do
              defaults [:read]
            end
          end
        end

      assert error.message =~ "is_valid?"
      assert error.message =~ "content"
      assert error.message =~ "union member"
    end

    test "rejects an invalid field name inside a map union member" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyUnionMemberNames.BadMemberField do
            @moduledoc false
            use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

            kotlin_multiplatform do
              type_name("BadMemberField")
            end

            attributes do
              uuid_primary_key :id

              attribute :content, :union do
                constraints types: [
                              note: [
                                type: :map,
                                constraints: [
                                  fields: [body: [type: :string], ok?: [type: :boolean]]
                                ]
                              ]
                            ]

                public? true
              end
            end

            actions do
              defaults [:read]
            end
          end
        end

      assert error.message =~ "ok?"
      assert error.message =~ "note"
      assert error.message =~ "content"
    end

    test "accepts valid union member and member field names" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyUnionMemberNames.GoodUnion do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("GoodUnion")
          end

          attributes do
            uuid_primary_key :id

            attribute :content, :union do
              constraints types: [
                            text: [type: :string],
                            note: [
                              type: :map,
                              constraints: [
                                fields: [body: [type: :string], pinned: [type: :boolean]]
                              ]
                            ]
                          ]

              public? true
            end
          end

          actions do
            defaults [:read]
          end
        end
      end
    end

    test "ignores constraint names the generator erases" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyUnionMemberNames.ErasedNames do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("ErasedNames")
          end

          attributes do
            uuid_primary_key :id

            # Becomes an untyped map in Kotlin: `is_valid?` is never emitted.
            attribute :settings, :map do
              constraints fields: [is_valid?: [type: :boolean]]
              public? true
            end

            # Becomes a List in Kotlin: `x_1` is never emitted.
            attribute :position, :tuple do
              constraints fields: [x_1: [type: :integer], y_1: [type: :integer]]
              public? true
            end
          end

          actions do
            defaults [:read]
          end
        end
      end
    end

    test "ignores a non-public union attribute" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyUnionMemberNames.PrivateUnion do
          @moduledoc false
          use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

          kotlin_multiplatform do
            type_name("PrivateUnion")
          end

          attributes do
            uuid_primary_key :id

            attribute :content, :union do
              constraints types: [is_valid?: [type: :boolean]]
            end
          end

          actions do
            defaults [:read]
          end
        end
      end
    end
  end
end
