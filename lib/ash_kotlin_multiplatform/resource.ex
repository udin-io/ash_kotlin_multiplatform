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

    kotlin do
      type_name "Todo"
      field_names [address_line_1: :addressLine1]
    end
  end
  ```
  """

  @kotlin %Spark.Dsl.Section{
    name: :kotlin,
    describe: "Define Kotlin settings for this resource",
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
        doc:
          "A keyword list mapping invalid argument names to valid alternatives per action (e.g., [read_with_invalid_arg: [is_active?: :isActive]])",
        default: []
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@kotlin]
end
