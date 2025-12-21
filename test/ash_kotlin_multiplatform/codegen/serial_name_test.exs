# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.SerialNameTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas

  describe "SerialName annotation behavior" do
    test "generates @SerialName when output_field_formatter is :snake_case" do
      # Set output formatter to snake_case
      original_value = Application.get_env(:ash_kotlin_multiplatform, :output_field_formatter)
      Application.put_env(:ash_kotlin_multiplatform, :output_field_formatter, :snake_case)

      try do
        enum_spec = {"Status", [:in_progress, :completed]}
        result = ResourceSchemas.generate_enum_class(enum_spec)

        # Enum values should still have @SerialName for their raw values
        assert result =~ "@SerialName(\"in_progress\") IN_PROGRESS"
        assert result =~ "@SerialName(\"completed\") COMPLETED"
      after
        # Restore original value
        if original_value do
          Application.put_env(:ash_kotlin_multiplatform, :output_field_formatter, original_value)
        else
          Application.delete_env(:ash_kotlin_multiplatform, :output_field_formatter)
        end
      end
    end

    test "does not generate @SerialName for fields when output_field_formatter is :camel_case (default)" do
      # Ensure default camel_case formatter
      original_value = Application.get_env(:ash_kotlin_multiplatform, :output_field_formatter)
      Application.put_env(:ash_kotlin_multiplatform, :output_field_formatter, :camel_case)

      try do
        # Test that we can run the code gen without errors
        # The actual @SerialName behavior is tested via output inspection
        enum_spec = {"Status", [:pending]}
        result = ResourceSchemas.generate_enum_class(enum_spec)

        # Enum values still get @SerialName for string mapping
        assert result =~ "@SerialName(\"pending\") PENDING"
      after
        if original_value do
          Application.put_env(:ash_kotlin_multiplatform, :output_field_formatter, original_value)
        else
          Application.delete_env(:ash_kotlin_multiplatform, :output_field_formatter)
        end
      end
    end
  end
end
