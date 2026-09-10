# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Verifiers.VerifyPublicActions do
  @moduledoc """
  Refuses to generate a Kotlin client for an action the resource marks internal.

  Ash documents `public? false` on an action as "internal-only and must not be
  exposed by API extensions" (`deps/ash/lib/ash/resource/actions/shared_options.ex`,
  ash 3.33.1). Nothing enforced that here: a `rpc_action` naming a non-public
  action produced a fully typed client function for it, and the mistake showed
  up — if at all — as a runtime failure long after the code shipped. An
  author who wrote `public? false` to keep an action off the wire got the
  opposite.

  Four places can expose one, and all four are checked:

    * the action a `rpc_action` names
    * the `read_action` a `rpc_action` uses to find records for update/destroy
    * the action a `typed_query` names
    * the read action behind a public relationship, which the client loads
      through the parent resource without ever naming it

  The relationship check only looks at destinations carrying the
  `AshKotlinMultiplatform.Resource` extension. A destination the generator does
  not know about produces no client type, so its read action is not reachable
  from Kotlin and is none of this verifier's business.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:kotlin_rpc])
    |> Enum.reduce_while(:ok, fn entity, acc ->
      case verify_resource(entity) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_resource(%{resource: resource} = entity) do
    rpc_actions = Map.get(entity, :rpc_actions, [])
    typed_queries = Map.get(entity, :typed_queries, [])

    with :ok <- verify_rpc_actions(resource, rpc_actions),
         :ok <- verify_typed_queries(resource, typed_queries) do
      verify_relationship_read_actions(resource)
    end
  end

  @doc false
  def verify_rpc_actions(resource, rpc_actions) do
    Enum.reduce_while(rpc_actions, :ok, fn rpc_action, acc ->
      with :ok <- verify_action_public(resource, rpc_action),
           :ok <- verify_read_action_public(resource, rpc_action) do
        {:cont, acc}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp verify_action_public(resource, rpc_action) do
    case Ash.Resource.Info.action(resource, rpc_action.action) do
      nil ->
        :ok

      action ->
        if public?(action) do
          :ok
        else
          error("""
          RPC action #{inspect(rpc_action.name)} on #{inspect(resource)} exposes action \
          #{inspect(action.name)}, which is not `public?`.

          Ash treats a non-public action as internal-only, so it must not reach a generated \
          Kotlin client.

          Either mark the action `public? true`, or drop `rpc_action #{inspect(rpc_action.name)}, \
          #{inspect(action.name)}` from the `kotlin_rpc` block.
          """)
        end
    end
  end

  defp verify_read_action_public(resource, rpc_action) do
    read_action_name = Map.get(rpc_action, :read_action)
    read_action = read_action_name && Ash.Resource.Info.action(resource, read_action_name)

    if read_action && not public?(read_action) do
      error("""
      RPC action #{inspect(rpc_action.name)} on #{inspect(resource)} uses read_action \
      #{inspect(read_action_name)}, which is not `public?`.

      The read_action fetches the record the client names, so exposing it over RPC exposes \
      whatever it can read.

      Either mark #{inspect(read_action_name)} `public? true`, or point `read_action` at a \
      public read action.
      """)
    else
      :ok
    end
  end

  @doc false
  def verify_typed_queries(resource, typed_queries) do
    Enum.reduce_while(typed_queries, :ok, fn typed_query, acc ->
      case Ash.Resource.Info.action(resource, typed_query.action) do
        nil ->
          {:cont, acc}

        action ->
          if public?(action) do
            {:cont, acc}
          else
            {:halt,
             error("""
             Typed query #{inspect(typed_query.name)} on #{inspect(resource)} references action \
             #{inspect(action.name)}, which is not `public?`.

             Ash treats a non-public action as internal-only, so it must not reach a generated \
             Kotlin client.

             Either mark the action `public? true`, or drop the \
             `typed_query #{inspect(typed_query.name)}` entry.
             """)}
          end
      end
    end)
  end

  @doc false
  def verify_relationship_read_actions(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.reduce_while(:ok, fn relationship, acc ->
      destination = relationship.destination

      with true <-
             AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_resource?(destination),
           read_action when not is_nil(read_action) <- resolve_read_action(relationship),
           false <- public?(read_action) do
        {:halt,
         error("""
         Relationship #{inspect(resource)}.#{relationship.name} points to #{inspect(destination)}, \
         whose read action #{inspect(read_action.name)} is not `public?`.

         The generated client loads a public relationship through its parent, which runs that read \
         action — so a non-public read action on the destination is exposed without ever being \
         named in the `kotlin_rpc` block.

         Either mark #{inspect(destination)}'s #{inspect(read_action.name)} action `public? true`, \
         or make the relationship `public? false`.
         """)}
      else
        _ -> {:cont, acc}
      end
    end)
  end

  defp resolve_read_action(relationship) do
    if relationship.read_action do
      Ash.Resource.Info.action(relationship.destination, relationship.read_action)
    else
      Ash.Resource.Info.primary_action(relationship.destination, :read)
    end
  end

  defp public?(action), do: Map.get(action, :public?, true)

  defp error(message) do
    {:error, Spark.Error.DslError.exception(message: String.trim_trailing(message))}
  end
end
