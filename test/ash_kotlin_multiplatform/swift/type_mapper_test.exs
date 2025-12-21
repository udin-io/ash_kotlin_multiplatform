# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Swift.TypeMapperTest do
  use ExUnit.Case, async: true

  alias AshKotlinMultiplatform.Swift.TypeMapper

  describe "get_swift_type_for_type/2" do
    test "maps primitive types correctly" do
      assert TypeMapper.get_swift_type_for_type(Ash.Type.String, []) == "String"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Integer, []) == "Int"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Float, []) == "Double"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Boolean, []) == "Bool"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Binary, []) == "Data"
    end

    test "maps UUID to String" do
      assert TypeMapper.get_swift_type_for_type(Ash.Type.UUID, []) == "String"
    end

    test "maps date/time types to String (ISO8601)" do
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Date, []) == "String"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Time, []) == "String"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.UtcDatetime, []) == "String"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.DateTime, []) == "String"
    end

    test "maps arrays correctly" do
      assert TypeMapper.get_swift_type_for_type({:array, Ash.Type.String}, []) == "[String]"
      assert TypeMapper.get_swift_type_for_type({:array, Ash.Type.Integer}, []) == "[Int]"
    end

    test "maps map types correctly" do
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Map, []) == "[String: Any]"
    end

    test "maps atom type to String" do
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Atom, []) == "String"
      assert TypeMapper.get_swift_type_for_type(Ash.Type.Atom, [one_of: [:a, :b]]) == "String"
    end
  end

  describe "get_swift_class_name/1" do
    test "extracts class name from module" do
      assert TypeMapper.get_swift_class_name(MyApp.Accounts.User) == "User"
      assert TypeMapper.get_swift_class_name(Todos.Todo) == "Todo"
    end
  end
end
