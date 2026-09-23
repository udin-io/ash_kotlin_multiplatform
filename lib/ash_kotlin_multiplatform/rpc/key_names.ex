# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.KeyNames do
  @moduledoc """
  Turns the keys of a client's `input`, `filter`, `page`, `identity` and
  `getBy` maps into internal names.

  Extracted from `AshKotlinMultiplatform.Rpc.Runner`, which is the only caller.
  It lives on its own because the return type of `internal_key/2` is the whole
  of issue #77 and a private function cannot be tested for it.

  ## The atom table is never grown here

  Nothing in this module calls `String.to_atom/1`. Keys come from the client,
  and the atom table is never garbage collected, so minting one atom per key
  let a caller looping on fresh names exhaust it and take the node down
  (issue #18).
  """

  alias AshIntrospection.ResourceInfo, as: SharedResourceInfo
  alias AshKotlinMultiplatform.Resource.Info, as: ResourceInfo

  @doc """
  Rewrites every string key of `term` to its internal name, recursively.

  A list is walked entry by entry, and any other value is returned unchanged.
  """
  @spec parse(term(), module() | nil, map()) :: term()
  def parse(map, resource, config) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        internal_key = internal_key(key, resource)
        {internal_key, parse_value(internal_key, value, resource, config)}

      {key, value} ->
        {key, parse(value, resource, config)}
    end)
  end

  def parse(list, resource, config) when is_list(list) do
    Enum.map(list, &parse(&1, resource, config))
  end

  def parse(value, _resource, _config), do: value

  @doc """
  The internal name a client key stands for.

  A `field_names` override is consulted before the generic camelCase parser,
  because the two disagree and only the override is right: the DSL maps
  `address_line_1` to the client name `addressLine1`, which the parser would
  turn back into `address_line1` — an attribute that does not exist. Inbound
  and outbound must resolve the same option or the client cannot send back
  what the server just sent it (#71).
  """
  @spec internal_key(String.t(), module() | nil) :: String.t() | atom()
  def internal_key(string, nil), do: existing_atom_key(string)

  def internal_key(string, resource) when is_binary(string) do
    case ResourceInfo.get_original_field_name(resource, string) do
      name when is_atom(name) and not is_nil(name) -> name
      _ -> existing_atom_key(string)
    end
  rescue
    _ -> existing_atom_key(string)
  end

  @doc """
  Rewrites a client key from camelCase to snake_case.
  """
  @spec snake_case(String.t()) :: String.t()
  def snake_case(string) when is_binary(string) do
    string
    |> String.replace(~r/([a-z])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  # `String.to_existing_atom/1`, never `String.to_atom/1`. A name no atom
  # exists for names no argument, attribute or option either, so leaving it a
  # string costs nothing: Ash rejects it downstream as an unknown key.
  defp existing_atom_key(string) when is_binary(string) do
    snake = snake_case(string)

    try do
      String.to_existing_atom(snake)
    rescue
      ArgumentError -> snake
    end
  end

  # An untyped `:map` attribute declares no field names of its own, so every
  # key under it is caller data, not something this DSL or Ash ever named.
  # Recursing into it with `parse/3` risked promoting a data key to an atom via
  # `internal_key/2`'s `String.to_existing_atom/1` whenever that word happened
  # to be interned somewhere else in the VM — dependent on load order, not on
  # this app's own atom budget (#18 stays closed either way, nothing here mints
  # one). The ash 3.33.4 bump made it deterministic: reactor 1.0.7's
  # `RetriesExceededError` interns `:retry_count` at load, and the wire test
  # data used exactly that word (#81). Once inside an untyped map's value, keys
  # are only ever snake_cased and kept as strings — this still applies the #71
  # casing rule that output formatting no longer undoes it, without ever
  # risking a mixed atom/string-keyed map.
  defp parse_value(key, value, resource, config) when is_atom(key) do
    if untyped_map_attribute?(resource, key, config) do
      stringify_keys(value)
    else
      parse(value, resource, config)
    end
  end

  defp parse_value(_key, value, resource, config), do: parse(value, resource, config)

  defp untyped_map_attribute?(resource, key, config) when not is_nil(resource) do
    case SharedResourceInfo.attribute(resource, key, config) do
      %{type: Ash.Type.Map, constraints: constraints} ->
        Keyword.get(constraints, :fields) in [nil, []]

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp untyped_map_attribute?(_resource, _key, _config), do: false

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {stringify_key(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp stringify_key(key) when is_binary(key), do: snake_case(key)
  defp stringify_key(key), do: key
end
