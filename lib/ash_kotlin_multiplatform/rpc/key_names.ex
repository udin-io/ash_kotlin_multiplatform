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

  ## One type out: always a string

  `internal_key/2` returned an atom when `String.to_existing_atom/1` found one
  and a string when it did not. One parsed map therefore held `:retry_count`
  beside `"created_by"`, and which of the two a given key got depended on the
  modules the VM had loaded at that moment rather than on the request (#77).
  Every key now comes back a string.

  ## The atom lookup moved to where the name is known

  The atoms existed to name a known argument, attribute or option, so
  `resolve/2` does that lookup against a list of names the caller already
  holds. Three callers in `Rpc.Runner` need it, and each one knows its own
  names:

  * `parse_pagination/2` — `Ash.Page.page_opts/1` reads `page[:limit]` and its
    siblings with atom keys (`deps/ash/lib/ash/page/page.ex:17`).
  * `parse_identity/3` — `AshIntrospection.Rpc.Pipeline` matches an identity
    against the resource's own attribute atoms with
    `Map.has_key?(identity, :id)`
    (`deps/ash_introspection/lib/ash_introspection/rpc/pipeline.ex:629`).
  * `parse_get_by/4` — the DSL's `get_by` list is atoms.

  `input` and `filter` need no atoms at all. `Ash.Changeset.for_create/4` and
  `Ash.Query.filter_input/2` read string keys, which is what a Phoenix
  controller hands them anyway.

  ## The atom table is never grown here

  Nothing in this module calls `String.to_atom/1`, and `resolve/2` compares
  against atoms that already exist because something declared them. A client
  looping on fresh key names still mints nothing (issue #18).
  """

  alias AshIntrospection.ResourceInfo, as: SharedResourceInfo
  alias AshKotlinMultiplatform.Resource.Info, as: ResourceInfo

  @doc """
  Rewrites every string key of `term` to its internal name, recursively.

  A list is walked entry by entry, and any other value is returned unchanged.
  Every key a client sent comes back a string; see `internal_key/2`.
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
  The internal name a client key stands for, always as a string.

  A `field_names` override is consulted before the generic camelCase parser,
  because the two disagree and only the override is right: the DSL maps
  `address_line_1` to the client name `addressLine1`, which the parser would
  turn back into `address_line1` — an attribute that does not exist. Inbound
  and outbound must resolve the same option or the client cannot send back
  what the server just sent it (#71).
  """
  @spec internal_key(String.t(), module() | nil) :: String.t()
  def internal_key(string, nil) when is_binary(string), do: snake_case(string)

  def internal_key(string, resource) when is_binary(string) do
    case ResourceInfo.get_original_field_name(resource, string) do
      name when is_atom(name) and not is_nil(name) -> Atom.to_string(name)
      _ -> snake_case(string)
    end
  rescue
    _ -> snake_case(string)
  end

  @doc """
  Replaces each key that names one of `known_names` with that atom.

  Every other key is left exactly as it is, so a name nothing declares stays a
  string and the consumer rejects it as the unknown option, attribute or field
  it is. `known_names` are atoms the caller already holds — a resource's
  attributes, Ash's page options, the DSL's `get_by` list — so no atom is
  minted and no client string ever reaches `String.to_atom/1`.
  """
  @spec resolve(map(), [atom()]) :: map()
  def resolve(map, known_names) when is_map(map) and is_list(known_names) do
    Map.new(map, fn {key, value} -> {known_name(key, known_names), value} end)
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

  defp known_name(key, known_names) when is_binary(key) do
    Enum.find(known_names, key, &(Atom.to_string(&1) == key))
  end

  defp known_name(key, _known_names), do: key

  # An untyped `:map` attribute declares no field names of its own, so every
  # key under it is caller data, not something this DSL or Ash ever named.
  # Recursing into it with `parse/3` would snake_case those keys, which #71
  # stopped output formatting from undoing, so `stringify_keys/1` applies the
  # casing rule and nothing else (#81).
  #
  # A `:map` attribute that DOES declare fields names them, and a declared
  # field name is a known name, so its keys resolve against that list. Ash
  # normalises a real typed map's keys itself
  # (`deps/ash/lib/ash/type/map.ex:466`), but this library answers from the
  # manifest, and an attribute the manifest declares fields for while the live
  # type stays untyped never reaches that code — `RunnerManifestSourceTest`
  # pins it.
  defp parse_value(key, value, resource, config) when is_binary(key) do
    case map_attribute_fields(resource, key, config) do
      nil -> parse(value, resource, config)
      [] -> stringify_keys(value)
      names -> value |> parse(resource, config) |> resolve_nested(names)
    end
  end

  defp parse_value(_key, value, resource, config), do: parse(value, resource, config)

  defp resolve_nested(value, names) when is_map(value), do: resolve(value, names)

  defp resolve_nested(value, names) when is_list(value),
    do: Enum.map(value, &resolve_nested(&1, names))

  defp resolve_nested(value, _names), do: value

  # `nil` when the attribute is not a `:map`, `[]` when it is an untyped one,
  # and the field names it declares otherwise.
  #
  # `SharedResourceInfo.attribute/3` takes the name as a string or an atom and
  # keys its lookup on both (`deps/ash/lib/ash/resource/transformers/
  # attributes_by_name.ex:19`), so the internal name goes in as it comes out of
  # `internal_key/2`.
  defp map_attribute_fields(resource, key, config) when not is_nil(resource) do
    case SharedResourceInfo.attribute(resource, key, config) do
      %{type: Ash.Type.Map, constraints: constraints} ->
        constraints |> Keyword.get(:fields, []) |> Kernel.||([]) |> Keyword.keys()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp map_attribute_fields(_resource, _key, _config), do: nil

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {stringify_key(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp stringify_key(key) when is_binary(key), do: snake_case(key)
  defp stringify_key(key), do: key
end
