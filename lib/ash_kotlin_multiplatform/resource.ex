# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Resource do
  @moduledoc """
  Spark DSL extension for configuring Kotlin generation on Ash resources.

  This extension allows resources to define Kotlin-specific settings,
  such as custom type names for the generated Kotlin data classes.

  ## Example

  ```elixir
  defmodule MyApp.Todo do
    use Ash.Resource,
      domain: MyApp.Domain,
      extensions: [AshKotlinMultiplatform.Resource]

    kotlin_multiplatform do
      type_name "Todo"
      field_names [address_line_1: :addressLine1]
    end
  end
  ```
  """

  @kotlin_multiplatform %Spark.Dsl.Section{
    name: :kotlin_multiplatform,
    describe: "Define Kotlin Multiplatform settings for this resource",
    schema: [
      type_name: [
        type: :string,
        doc: "The name of the Kotlin data class for the resource",
        required: true
      ],
      field_names: [
        type: :keyword_list,
        doc:
          "A keyword list mapping invalid field names to valid alternatives (e.g., [address_line_1: :addressLine1])",
        default: []
      ],
      argument_names: [
        type: :keyword_list,
        doc: """
        A keyword list mapping argument names to the names the Kotlin client uses, per Ash action name (e.g., `[create: [confirm?: :confirmed]]`).

        The override is the wire name, used verbatim, and the server accepts it as well as the raw argument name. An exposed argument whose name contains `?` needs one. An entry naming no action, no argument on it, an invalid name, or a name another input of the action already uses is a compile error.
        """,
        default: []
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@kotlin_multiplatform],
    verifiers: [
      AshKotlinMultiplatform.Resource.Verifiers.VerifyFieldNames,
      AshKotlinMultiplatform.Resource.Verifiers.VerifyUnionMemberNames,
      AshKotlinMultiplatform.Resource.Verifiers.VerifyUniqueTypeNames
    ]
end
