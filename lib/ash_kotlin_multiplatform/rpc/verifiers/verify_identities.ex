# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Verifiers.VerifyIdentities do
  @moduledoc """
  Verifies the lookup keys an RPC action names actually exist on the resource.

  Two options name a way to select a record, and both are checked here because a
  wrong name otherwise fails at runtime with an Ash error the client author
  cannot trace back to the DSL entry that caused it:

  * `identities` on an update or destroy — each must be `:_primary_key` or an
    identity defined on the resource.
  * `get_by` on a read — each must be a public attribute. The generated `GetBy`
    data class takes its Kotlin type from that attribute, so a name that is not
    one has no type to emit.

  `get_by` on anything other than a read is also rejected here (#69). The
  generator emits the `getBy` config field for read actions only
  (`Rpc.Codegen.Helpers.ConfigBuilder.get_action_context/3`), so a create,
  update or destroy carrying `get_by` compiled clean, shipped a client that
  could not send the field, and failed every call with
  `{:missing_get_by_fields, ...}`. A compile error at the offending line beats a
  runtime error on every request.

  `get?`, `not_found_error?`, `enable_filter?` and `enable_sort?` are all
  documented "Read actions only" and get the same refusal (#79). `get?` on a
  non-read was a silent decode mismatch: `ConfigBuilder`'s `is_get_action` and
  `Runner.apply_get?/2` both match a read only, so the generated Kotlin was
  shaped as a single-record call against a server that still returned the
  list or the written record. `not_found_error?`, `enable_filter?` and
  `enable_sort?` have no reader at all on a non-read — they only ever
  mattered to a `get?` read or a list read — so a value set there did nothing,
  the same gap under a different option.

  Each of the four is checked against its own default (the value it would
  hold if never set), because Spark applies defaults into the struct before
  this verifier runs: a value equal to the default is indistinguishable from
  absent, and is let through.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  # {struct key, default value, DSL option name}. A non-read rpc_action may
  # only carry the default for each — anything else has no reader on a
  # non-read action, so it silently does nothing.
  @read_only_options [
    {:get?, false, "get?"},
    {:not_found_error?, true, "not_found_error?"},
    {:enable_filter?, true, "enable_filter?"},
    {:enable_sort?, true, "enable_sort?"}
  ]

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:kotlin_rpc])
    |> Enum.reduce_while(:ok, fn %{resource: resource, rpc_actions: rpc_actions}, acc ->
      case verify_identities(resource, rpc_actions) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_identities(resource, rpc_actions) do
    errors =
      Enum.reduce(rpc_actions, [], fn rpc_action, acc ->
        validate_rpc_action_identities(resource, rpc_action, acc)
      end)

    case errors do
      [] -> :ok
      _ -> format_identity_validation_errors(errors)
    end
  end

  defp validate_rpc_action_identities(resource, rpc_action, errors) do
    action = Ash.Resource.Info.action(resource, rpc_action.action)

    cond do
      is_nil(action) ->
        errors

      action.type == :read ->
        validate_get_by_fields(resource, rpc_action, errors)

      action.type in [:update, :destroy] ->
        identities = Map.get(rpc_action, :identities, [:_primary_key])

        errors =
          errors
          |> validate_get_by_absent(rpc_action, action)
          |> validate_read_only_options_absent(rpc_action, action)

        validate_identities_exist(resource, rpc_action, identities, errors)

      true ->
        errors
        |> validate_get_by_absent(rpc_action, action)
        |> validate_read_only_options_absent(rpc_action, action)
    end
  end

  defp validate_get_by_absent(errors, rpc_action, action) do
    case rpc_action |> Map.get(:get_by) |> List.wrap() do
      [] ->
        errors

      fields ->
        [{:get_by_on_non_read, rpc_action.name, rpc_action.action, action.type, fields} | errors]
    end
  end

  defp validate_read_only_options_absent(errors, rpc_action, action) do
    Enum.reduce(@read_only_options, errors, fn {key, default, label}, acc ->
      case Map.get(rpc_action, key, default) do
        ^default ->
          acc

        _value ->
          [
            {:read_only_option_on_non_read, label, rpc_action.name, rpc_action.action,
             action.type}
            | acc
          ]
      end
    end)
  end

  defp validate_get_by_fields(resource, rpc_action, errors) do
    public_attributes =
      resource |> Ash.Resource.Info.public_attributes() |> Enum.map(& &1.name)

    rpc_action
    |> Map.get(:get_by)
    |> List.wrap()
    |> Enum.reduce(errors, fn field, acc ->
      if field in public_attributes do
        acc
      else
        [{:get_by_not_an_attribute, rpc_action.name, field, public_attributes} | acc]
      end
    end)
  end

  defp validate_identities_exist(resource, rpc_action, identities, errors) do
    Enum.reduce(identities, errors, fn identity, acc ->
      case identity do
        :_primary_key ->
          # Verify the resource actually has a primary key
          case Ash.Resource.Info.primary_key(resource) do
            [] ->
              [
                {:no_primary_key, rpc_action.name, rpc_action.action, resource}
                | acc
              ]

            _ ->
              acc
          end

        identity_name when is_atom(identity_name) ->
          # Check if the identity exists on the resource
          if Ash.Resource.Info.identity(resource, identity_name) do
            acc
          else
            available_identities = get_available_identities(resource)

            [
              {:identity_not_found, rpc_action.name, rpc_action.action, identity_name,
               available_identities}
              | acc
            ]
          end

        _ ->
          acc
      end
    end)
  end

  defp get_available_identities(resource) do
    resource
    |> Ash.Resource.Info.identities()
    |> Enum.map(& &1.name)
  end

  defp format_identity_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid record lookup configuration found in RPC actions.

       #{message_parts}

       Each identity listed in the `identities` option must either be `:_primary_key` (for the resource's primary key)
       or the name of an identity defined on the resource. Each field listed in `get_by` must be a public attribute.
       `get?`, `get_by`, `not_found_error?`, `enable_filter?` and `enable_sort?` may only be set on a read action.
       """
     )}
  end

  defp format_error_part({:get_by_on_non_read, rpc_name, action_name, action_type, fields}) do
    """
    get_by is set on an action that is not a read:
      - RPC action: #{rpc_name} (action: #{action_name}, type: #{inspect(action_type)})
      - Fields: #{Enum.map_join(fields, ", ", &inspect/1)}
      - #{get_by_replacement(action_type)}
    """
  end

  defp format_error_part(
         {:read_only_option_on_non_read, option, rpc_name, action_name, action_type}
       ) do
    """
    #{option} is set on an action that is not a read:
      - RPC action: #{rpc_name} (action: #{action_name}, type: #{inspect(action_type)})
      - Remove `#{option}` from this action; it only affects a read.
    """
  end

  defp format_error_part({:get_by_not_an_attribute, rpc_name, field, public_attributes}) do
    available_str =
      case public_attributes do
        [] -> "No public attributes are defined on this resource."
        attributes -> "Public attributes: #{Enum.map_join(attributes, ", ", &inspect/1)}"
      end

    """
    get_by field is not a public attribute:
      - RPC action: #{rpc_name}
      - Field: #{inspect(field)}
      - #{available_str}
    """
  end

  defp format_error_part(
         {:identity_not_found, rpc_name, action_name, identity_name, available_identities}
       ) do
    available_str =
      case available_identities do
        [] ->
          "No identities are defined on this resource."

        identities ->
          "Available identities: #{Enum.map_join(identities, ", ", &inspect/1)}"
      end

    """
    Identity not found on resource:
      - RPC action: #{rpc_name} (action: #{action_name})
      - Identity: #{inspect(identity_name)}
      - #{available_str}
      - Note: Use `:_primary_key` to reference the resource's primary key.
    """
  end

  defp format_error_part({:no_primary_key, rpc_name, action_name, resource}) do
    """
    Resource has no primary key but :_primary_key identity is configured:
      - RPC action: #{rpc_name} (action: #{action_name})
      - Resource: #{inspect(resource)}
      - Either define a primary key on the resource, use a named identity, or use `identities: []` for actor-scoped actions.
    """
  end

  defp get_by_replacement(type) when type in [:update, :destroy],
    do:
      "Use `identities` to name the lookup key for an update or destroy. `get_by` selects a record on a read only."

  defp get_by_replacement(:action),
    do: "A generic action returns what its `returns` declares. Remove `get_by` from this action."

  defp get_by_replacement(_type),
    do: "A create looks up no record. Remove `get_by` from this action."
end
