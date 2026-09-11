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
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

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

      action.type in [:update, :destroy] ->
        identities = Map.get(rpc_action, :identities, [:_primary_key])
        validate_identities_exist(resource, rpc_action, identities, errors)

      action.type == :read ->
        validate_get_by_fields(resource, rpc_action, errors)

      true ->
        errors
    end
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
       """
     )}
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
end
