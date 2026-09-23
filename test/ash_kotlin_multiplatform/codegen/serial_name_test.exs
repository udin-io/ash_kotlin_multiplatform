# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Codegen.SerialNameTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Codegen.ResourceSchemas

  # `output_field_formatter` renames record FIELDS
  # (`ResourceSchemas` lines 416 and 430). `generate_enum_class/1` never reads
  # it: an entry's `@SerialName` is `Atom.to_string/1` of the value, so the wire
  # value survives every formatter setting. These cases used to set the key with
  # `Application.put_env/3` and restore it in an `after`, which asserted nothing
  # the function does and put a VM-global write inside an `async: true` file —
  # the shape that made install_test flake (#108).
  describe "generate_enum_class/1" do
    test "serialises a multi-word value as the raw atom, not a formatted name" do
      result = ResourceSchemas.generate_enum_class({"Status", [:in_progress, :completed]})

      assert result =~ "@SerialName(\"in_progress\") IN_PROGRESS"
      assert result =~ "@SerialName(\"completed\") COMPLETED"
    end

    test "serialises a single-word value as the raw atom" do
      result = ResourceSchemas.generate_enum_class({"Status", [:pending]})

      assert result =~ "@SerialName(\"pending\") PENDING"
    end
  end
end
