# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Runner do
  @moduledoc """
  RPC action runner for Kotlin client requests.

  This module handles discovering and executing RPC actions configured via
  the `kotlin_rpc` DSL extension. It provides a standard interface for
  processing requests from Kotlin clients.

  ## Usage

  Typically used via `AshKotlinMultiplatform.Phoenix.Controller`, but can
  also be called directly:

      result = AshKotlinMultiplatform.Rpc.Runner.run_action(:my_app, params, actor: user)

  ## Request Format

  The params map should contain:
  - `"action"` - The RPC action name (e.g., "list_todos", "create_todo")
  - `"input"` - Input parameters for the action
  - `"fields"` - Fields to select/return (sparse fieldsets). A list whose entries
    are either a field name (`"title"`) or a map naming a relationship,
    calculation or embedded field and the fields to take from it
    (`%{"author" => ["id", "name"]}`), nested to any depth. Absent or `[]`
    returns every public attribute and nothing else. Selection is resolved by
    `AshIntrospection.Rpc.FieldProcessing.FieldSelector`, so an unknown name is
    an error rather than silently dropped, and a relationship whose destination
    the `kotlin_rpc` DSL does not publish is refused.
  - `"identity"` - Identity for update/destroy actions
  - `"filter"` - Filter for read actions
  - `"sort"` - Sort string for read actions
  - `"page"` - Pagination options
  - `"metadataFields"` - Metadata fields to return. Narrows the fields the DSL
    exposes; it can never widen them. Absent or `nil` returns every exposed
    field, `[]` returns none.

  ## Response Format

  Returns a map with:
  - `"success"` - Boolean indicating success
  - `"data"` - The action result (on success)
  - `"errors"` - List of error objects (on failure)
  - `"metadata"` - Optional metadata from the action
  """

  alias AshKotlinMultiplatform.Rpc.Info
  alias AshKotlinMultiplatform.Rpc.Pipeline
  alias AshIntrospection.Rpc.ErrorBuilder
  alias AshIntrospection.Rpc.FieldProcessing.FieldSelector
  alias AshIntrospection.Rpc.Request
  alias AshIntrospection.FieldFormatter

  @doc """
  Execute an RPC action based on the request parameters.

  ## Parameters

  - `otp_app` - The OTP application name
  - `params` - Map containing action, input, fields, identity, etc.
  - `opts` - Keyword list with:
    - `:actor` - The authenticated user
    - `:tenant` - Tenant (if multi-tenant)
    - `:context` - Additional context

  ## Returns

  A map with `"success"`, `"data"`, and/or `"errors"` keys.
  """
  def run_action(otp_app, params, opts \\ []) do
    action_name = params["action"]
    actor = Keyword.get(opts, :actor)
    tenant = Keyword.get(opts, :tenant)
    context = Keyword.get(opts, :context, %{})

    case discover_action(otp_app, action_name) do
      {:ok, {domain, resource, rpc_action}} ->
        execute_action(domain, resource, rpc_action, params, actor, tenant, context)

      {:error, reason} ->
        build_error_response(reason)
    end
  end

  @doc """
  Validate an RPC action without executing it.

  Useful for real-time validation in client applications.
  """
  def validate_action(otp_app, params, opts \\ []) do
    action_name = params["action"]
    actor = Keyword.get(opts, :actor)
    tenant = Keyword.get(opts, :tenant)

    case discover_action(otp_app, action_name) do
      {:ok, {domain, resource, rpc_action}} ->
        validate_changeset(domain, resource, rpc_action, params, actor, tenant)

      {:error, reason} ->
        build_error_response(reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Action Discovery
  # ---------------------------------------------------------------------------

  defp discover_action(otp_app, action_name) when is_binary(action_name) do
    domains = Ash.Info.domains(otp_app)

    result =
      Enum.find_value(domains, fn domain ->
        rpc_resources = Info.kotlin_rpc(domain)

        Enum.find_value(rpc_resources, fn %{resource: resource, rpc_actions: rpc_actions} ->
          Enum.find_value(rpc_actions, fn rpc_action ->
            if to_string(rpc_action.name) == action_name do
              {domain, resource, rpc_action}
            end
          end)
        end)
      end)

    case result do
      nil -> {:error, {:action_not_found, action_name}}
      found -> {:ok, found}
    end
  end

  defp discover_action(_otp_app, _), do: {:error, {:missing_required_parameter, :action}}

  # ---------------------------------------------------------------------------
  # Action Execution
  # ---------------------------------------------------------------------------

  defp execute_action(domain, resource, rpc_action, params, actor, tenant, context) do
    action_name = rpc_action.action
    action_info = resource |> Ash.Resource.Info.action(action_name) |> apply_get?(rpc_action)

    with {:ok, request} <-
           build_request(
             domain,
             resource,
             action_info,
             rpc_action,
             params,
             actor,
             tenant,
             context
           ),
         {:ok, ash_result} <- Pipeline.execute_ash_action(request),
         {:ok, processed} <- Pipeline.process_result(ash_result, request) do
      # `format_data/2` and not `format_output/1`: the latter renames field names
      # and never looks at a value, so a vector left here as the packed binary
      # `Jason` refuses (#71). `format_data/2` returns the payload alone, which
      # is what lets this library keep its own envelope below.
      processed
      |> Pipeline.format_data(request)
      |> build_success_response()
    else
      {:error, error} ->
        build_error_response(error)
    end
  end

  defp build_request(domain, resource, action, rpc_action, params, actor, tenant, context) do
    input = parse_input(params, resource)
    fields = params["fields"] || []
    identity = parse_identity(params, resource)
    filter = parse_filter(params, resource)
    sort = parse_sort(params)
    page = parse_pagination(params)

    show_metadata =
      action
      |> dsl_metadata_fields(rpc_action)
      |> narrow_metadata_fields(parse_metadata_fields(params))

    with :ok <- check_read_surface(rpc_action, filter, sort),
         {:ok, get_by} <- parse_get_by(params, rpc_action, resource),
         {:ok, {select, load, extraction_template}} <-
           select_fields(resource, action, fields) do
      {:ok,
       %Request{
         domain: domain,
         resource: resource,
         action: action,
         rpc_action: rpc_action,
         input: input,
         identity: identity,
         get_by: get_by,
         filter: filter,
         sort: sort,
         pagination: page,
         actor: actor,
         tenant: tenant,
         context: context,
         extraction_template: extraction_template,
         select: select,
         load: load,
         show_metadata: show_metadata
       }}
    end
  end

  defp validate_changeset(domain, resource, rpc_action, params, actor, tenant) do
    action_name = rpc_action.action
    action_info = Ash.Resource.Info.action(resource, action_name)
    input = parse_input(params, resource)

    opts = [
      actor: actor,
      tenant: tenant,
      domain: domain
    ]

    result =
      case action_info.type do
        :create ->
          changeset = Ash.Changeset.for_create(resource, action_name, input, opts)
          {:ok, changeset}

        :update ->
          identity = parse_identity(params, resource)

          with {:ok, record} <- get_record_for_validation(resource, identity, opts) do
            changeset = Ash.Changeset.for_update(record, action_name, input, opts)
            {:ok, changeset}
          end

        _ ->
          {:error, :validation_not_supported}
      end

    case result do
      {:ok, %Ash.Changeset{valid?: true}} ->
        build_validation_success_response()

      {:ok, %Ash.Changeset{valid?: false, errors: errors}} ->
        build_validation_error_response(errors)

      {:error, :validation_not_supported} ->
        %{
          "success" => false,
          "errors" => [
            %{
              "type" => "unsupported",
              "message" => "Validation is only supported for create and update actions",
              "shortMessage" => "Unsupported"
            }
          ]
        }

      {:error, error} ->
        build_error_response(error)
    end
  end

  defp get_record_for_validation(resource, identity, opts) when not is_nil(identity) do
    Ash.get(resource, identity, opts)
  end

  defp get_record_for_validation(_resource, nil, _opts) do
    {:error, {:missing_required_parameter, :identity}}
  end

  # ---------------------------------------------------------------------------
  # Single-Record Reads
  # ---------------------------------------------------------------------------

  # `AshIntrospection.Rpc.Pipeline.execute_read_action/3` branches on the *Ash*
  # action's `get?`, so a DSL-level `get?` has to reach it as one. Only the
  # branch decision reads the field — the query is built from `action.name` —
  # so overriding it here selects `Ash.read_one/1` and nothing else.
  #
  # `get_by` implies `get?`: naming the fields that select one record is the
  # whole statement, and requiring both would let a config ask for a lookup key
  # and a list in the same breath.
  defp apply_get?(%{type: :read} = action, rpc_action) do
    if Map.get(rpc_action, :get?, false) or configured_get_by(rpc_action) != [] do
      %{action | get?: true}
    else
      action
    end
  end

  defp apply_get?(action, _rpc_action), do: action

  defp configured_get_by(rpc_action), do: Map.get(rpc_action, :get_by) || []

  # The client must send exactly the fields the DSL configured — no more, no
  # fewer. A missing field would widen the lookup to every record matching the
  # rest, and `Ash.read_one/1` answers that with a `MultipleResults` naming
  # nothing the caller can act on; an extra field would reach
  # `Ash.Query.do_filter/2` as an arbitrary predicate.
  defp parse_get_by(params, rpc_action, resource) do
    allowed = configured_get_by(rpc_action)
    sent = normalize_get_by(params["getBy"], resource)

    sent_keys = sent |> Map.keys() |> MapSet.new()
    allowed_keys = MapSet.new(allowed)

    missing = allowed_keys |> MapSet.difference(sent_keys) |> Enum.sort()
    extra = sent_keys |> MapSet.difference(allowed_keys) |> Enum.sort()

    cond do
      extra != [] -> {:error, {:unexpected_get_by_fields, extra, allowed}}
      missing != [] -> {:error, {:missing_get_by_fields, missing}}
      allowed == [] -> {:ok, nil}
      true -> {:ok, sent}
    end
  end

  defp normalize_get_by(get_by, resource) when is_map(get_by),
    do: convert_keys_to_atoms(get_by, resource)

  defp normalize_get_by(_, _resource), do: %{}

  # ---------------------------------------------------------------------------
  # Read Surface
  # ---------------------------------------------------------------------------

  # `enable_filter?: false` and `enable_sort?: false` drop the parameter from the
  # generated config class, so no current client can send it. Rejecting rather
  # than dropping is the point: a stale client that still sends `filter` would
  # otherwise be handed the whole table and have no way to know it asked for a
  # subset. Same reasoning the core applied to `identity` on reads.
  defp check_read_surface(rpc_action, filter, sort) do
    cond do
      not is_nil(filter) and not Map.get(rpc_action, :enable_filter?, true) ->
        {:error, {:filter_not_supported, rpc_action.name}}

      not is_nil(sort) and not Map.get(rpc_action, :enable_sort?, true) ->
        {:error, {:sort_not_supported, rpc_action.name}}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Metadata Field Selection
  # ---------------------------------------------------------------------------

  # What the DSL exposes: nil means every field the action declares, false or []
  # means none, a list means exactly that list.
  defp dsl_metadata_fields(action, rpc_action) do
    case Map.get(rpc_action, :show_metadata) do
      nil -> action_metadata_fields(action)
      false -> []
      list when is_list(list) -> list
      _ -> []
    end
  end

  # The client can only narrow, never widen. Filtering the DSL list means a name
  # the DSL withholds yields nothing and no error that would reveal it exists.
  # nil means the client asked for nothing in particular, so it gets everything.
  defp narrow_metadata_fields(dsl_fields, nil), do: dsl_fields

  defp narrow_metadata_fields(dsl_fields, requested) do
    Enum.filter(dsl_fields, &(&1 in requested))
  end

  # Get all metadata field names from an action
  defp action_metadata_fields(action) do
    case Map.get(action, :metadata) do
      nil ->
        []

      metadata when is_list(metadata) ->
        Enum.map(metadata, fn
          %{name: name} -> name
          {name, _} -> name
          name when is_atom(name) -> name
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  # ---------------------------------------------------------------------------
  # Input Parsing
  # ---------------------------------------------------------------------------

  defp parse_input(params, resource) do
    input = params["input"] || %{}
    convert_keys_to_atoms(input, resource)
  end

  defp parse_identity(params, resource) do
    case params["identity"] do
      nil -> nil
      id when is_binary(id) -> id
      id when is_map(id) -> convert_keys_to_atoms(id, resource)
      id -> id
    end
  end

  defp parse_filter(params, resource) do
    case params["filter"] do
      nil -> nil
      filter -> convert_keys_to_atoms(filter, resource)
    end
  end

  defp parse_sort(params) do
    case params["sort"] do
      nil -> nil
      sort when is_binary(sort) -> Pipeline.format_sort_string(sort)
      sort -> sort
    end
  end

  defp parse_pagination(params) do
    case params["page"] do
      nil -> nil
      page -> convert_keys_to_atoms(page, nil)
    end
  end

  # nil means the client sent nothing, which keeps today's behaviour: everything
  # the DSL exposes. An empty list means no metadata.
  defp parse_metadata_fields(params) do
    case params["metadataFields"] do
      fields when is_list(fields) -> Enum.flat_map(fields, &existing_metadata_atom/1)
      _ -> nil
    end
  end

  # String.to_existing_atom/1 stops a client from growing the atom table. A name
  # that does not resolve is dropped rather than raised on: an atom that does not
  # exist cannot name a metadata field either, so there is nothing to report.
  defp existing_metadata_atom(name) when is_binary(name) do
    [name |> to_snake_case() |> String.to_existing_atom()]
  rescue
    ArgumentError -> []
  end

  defp existing_metadata_atom(name) when is_atom(name) and not is_nil(name), do: [name]
  defp existing_metadata_atom(_), do: []

  defp convert_keys_to_atoms(map, resource) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        {to_internal_key(key, resource), convert_keys_to_atoms(value, resource)}

      {key, value} ->
        {key, convert_keys_to_atoms(value, resource)}
    end)
  end

  defp convert_keys_to_atoms(list, resource) when is_list(list) do
    Enum.map(list, &convert_keys_to_atoms(&1, resource))
  end

  defp convert_keys_to_atoms(value, _resource), do: value

  # A `field_names` override is consulted before the generic camelCase parser,
  # because the two disagree and only the override is right: the DSL maps
  # `address_line_1` to the client name `addressLine1`, which the parser would
  # turn back into `address_line1` — an attribute that does not exist. Inbound
  # and outbound must resolve the same option or the client cannot send back
  # what the server just sent it (#71).
  defp to_internal_key(string, nil), do: to_snake_case_key(string)

  defp to_internal_key(string, resource) when is_binary(string) do
    case AshKotlinMultiplatform.Resource.Info.get_original_field_name(resource, string) do
      name when is_atom(name) and not is_nil(name) -> name
      _ -> to_snake_case_key(string)
    end
  rescue
    _ -> to_snake_case_key(string)
  end

  # `String.to_existing_atom/1`, never `String.to_atom/1`. These keys come from
  # the client's `input`, `filter`, `page` and `identity` maps, and the atom
  # table is never garbage collected, so minting one atom per key let a caller
  # looping on fresh names exhaust it and take the node down (issue #18). A name
  # no atom exists for names no argument, attribute or option either, so leaving
  # it a string costs nothing: Ash rejects it downstream as an unknown key.
  defp to_snake_case_key(string) when is_binary(string) do
    snake = to_snake_case(string)

    try do
      String.to_existing_atom(snake)
    rescue
      ArgumentError -> snake
    end
  end

  defp to_snake_case(string) when is_binary(string) do
    string
    |> String.replace(~r/([a-z])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  # ---------------------------------------------------------------------------
  # Field Selection
  # ---------------------------------------------------------------------------

  # An empty request keeps the existing contract: every public attribute, no
  # relationships, calculations or aggregates. The client asked for nothing in
  # particular, so it gets the resource's own flat shape.
  defp select_fields(resource, _action, []) do
    template = Enum.map(Ash.Resource.Info.public_attributes(resource), & &1.name)
    {:ok, {template, [], template}}
  end

  defp select_fields(resource, action, fields) when is_list(fields) do
    case FieldSelector.process(resource, action.name, fields, field_selector_config()) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:invalid_fields, reason}}
    end
  end

  defp select_fields(_resource, _action, fields) do
    {:error, {:invalid_fields, {:fields_must_be_a_list, fields}}}
  end

  # `is_interop_resource?` is what stops a nested request walking out of the
  # published graph: without it `FieldSelector` treats every Ash resource as
  # traversable, so a relationship to a resource the `kotlin_rpc` DSL never
  # exposed would become readable the moment nested selection started working.
  defp field_selector_config do
    Map.put(
      Pipeline.build_config(),
      :is_interop_resource?,
      &AshKotlinMultiplatform.Resource.Info.kotlin_multiplatform_resource?/1
    )
  end

  # ---------------------------------------------------------------------------
  # Response Building
  # ---------------------------------------------------------------------------

  defp build_success_response(data) do
    formatter = AshKotlinMultiplatform.output_field_formatter()

    base = %{
      FieldFormatter.format_field_name("success", formatter) => true,
      FieldFormatter.format_field_name("data", formatter) => data
    }

    base
  end

  defp build_validation_success_response do
    %{"success" => true, "valid" => true}
  end

  defp build_validation_error_response(errors) do
    formatted_errors = format_validation_errors(errors)

    %{
      "success" => true,
      "valid" => false,
      "errors" => formatted_errors
    }
  end

  defp format_validation_errors(errors) do
    Enum.map(List.wrap(errors), fn error ->
      %{
        "type" => "validation_error",
        "message" => Exception.message(error),
        "shortMessage" => "Validation failed",
        "field" => get_error_field(error)
      }
    end)
  end

  # Field selection and getBy errors carry a field path and a suggestion the
  # client can act on, so they are rendered from the shared `ErrorBuilder`
  # rather than flattened into a generic "error". The message arrives as a
  # template plus vars, which `render_message/2` fills in.
  defp build_error_response({:invalid_fields, _reason} = error),
    do: build_error_response_from_builder(error)

  defp build_error_response({:missing_get_by_fields, _missing} = error),
    do: build_error_response_from_builder(error)

  defp build_error_response({:unexpected_get_by_fields, _extra, _allowed} = error),
    do: build_error_response_from_builder(error)

  defp build_error_response({:invalid_get_by, _details} = error),
    do: build_error_response_from_builder(error)

  # Raised by the core pipeline, not here: a read that is sent an `identity` is
  # refused. The shared message names `get_by` as the replacement, which is the
  # reason this clause is worth having over the generic `inspect/1` fallback.
  defp build_error_response({:identity_not_supported, _details} = error),
    do: build_error_response_from_builder(error)

  defp build_error_response({:filter_not_supported, rpc_action_name}) do
    unsupported_read_parameter_response("filter", rpc_action_name, "enable_filter?")
  end

  defp build_error_response({:sort_not_supported, rpc_action_name}) do
    unsupported_read_parameter_response("sort", rpc_action_name, "enable_sort?")
  end

  defp build_error_response({:action_not_found, action_name}) do
    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "action_not_found",
          "message" => "RPC action '#{action_name}' not found",
          "shortMessage" => "Action not found"
        }
      ]
    }
  end

  defp build_error_response({:missing_required_parameter, param}) do
    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "missing_required_parameter",
          "message" => "Required parameter '#{param}' is missing",
          "shortMessage" => "Missing parameter"
        }
      ]
    }
  end

  defp build_error_response(%Ash.Error.Invalid{errors: errors}) do
    formatted_errors =
      Enum.map(errors, fn error ->
        %{
          "type" => "validation_error",
          "message" => Exception.message(error),
          "shortMessage" => "Validation failed",
          "field" => get_error_field(error)
        }
      end)

    %{"success" => false, "errors" => formatted_errors}
  end

  defp build_error_response(%Ash.Error.Forbidden{} = error) do
    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "forbidden",
          "message" => Exception.message(error),
          "shortMessage" => "Access denied"
        }
      ]
    }
  end

  defp build_error_response(%Ash.Error.Query.NotFound{} = error) do
    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "not_found",
          "message" => Exception.message(error),
          "shortMessage" => "Not found"
        }
      ]
    }
  end

  defp build_error_response({:missing_identity, details}) do
    expected = Map.get(details, :expected_keys, []) |> Enum.join(", ")

    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "missing_identity",
          "message" => "Identity required. Expected one of: #{expected}",
          "shortMessage" => "Missing identity"
        }
      ]
    }
  end

  defp build_error_response({:invalid_identity, details}) do
    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "invalid_identity",
          "message" => Map.get(details, :message, "Invalid identity provided"),
          "shortMessage" => "Invalid identity"
        }
      ]
    }
  end

  defp build_error_response(errors) when is_list(errors) do
    formatted_errors =
      Enum.flat_map(errors, fn
        %Ash.Error.Invalid{errors: inner_errors} ->
          Enum.map(inner_errors, &format_single_error/1)

        error ->
          [format_single_error(error)]
      end)

    %{"success" => false, "errors" => formatted_errors}
  end

  defp build_error_response(error) when is_exception(error) do
    %{
      "success" => false,
      "errors" => [format_single_error(error)]
    }
  end

  defp build_error_response(error) do
    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "error",
          "message" => inspect(error),
          "shortMessage" => "Error"
        }
      ]
    }
  end

  defp render_message(message, vars) when is_binary(message) and is_map(vars) do
    Enum.reduce(vars, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp build_error_response_from_builder(reason) do
    errors =
      reason
      |> ErrorBuilder.build_error_response(Pipeline.build_config())
      |> List.wrap()
      |> Enum.map(fn error ->
        %{
          "type" => to_string(error.type),
          "message" => render_message(error.message, Map.get(error, :vars, %{})),
          "shortMessage" => error.short_message,
          "field" => error |> Map.get(:fields, []) |> List.first() |> field_name_or_nil()
        }
      end)

    %{"success" => false, "errors" => errors}
  end

  # `fields` reaches here as strings from field selection and as atoms from the
  # getBy checks, and the client reads one shape.
  defp field_name_or_nil(nil), do: nil
  defp field_name_or_nil(field), do: to_string(field)

  defp unsupported_read_parameter_response(parameter, rpc_action_name, dsl_option) do
    %{
      "success" => false,
      "errors" => [
        %{
          "type" => "#{parameter}_not_supported",
          "message" =>
            "RPC action '#{rpc_action_name}' does not accept '#{parameter}'. " <>
              "Set `#{dsl_option} true` on the rpc_action to enable it, or regenerate the client.",
          "shortMessage" => "#{String.capitalize(parameter)} not supported"
        }
      ]
    }
  end

  defp format_single_error(error) when is_exception(error) do
    %{
      "type" => error_type(error),
      "message" => Exception.message(error),
      "shortMessage" => short_message(error),
      "field" => get_error_field(error)
    }
  end

  defp format_single_error(error) do
    %{
      "type" => "error",
      "message" => inspect(error),
      "shortMessage" => "Error"
    }
  end

  defp error_type(%Ash.Error.Changes.Required{}), do: "required"
  defp error_type(%Ash.Error.Changes.InvalidAttribute{}), do: "invalid_attribute"
  defp error_type(%Ash.Error.Query.NotFound{}), do: "not_found"
  defp error_type(%Ash.Error.Forbidden{}), do: "forbidden"
  defp error_type(_), do: "validation_error"

  defp short_message(%Ash.Error.Changes.Required{}), do: "Required"
  defp short_message(%Ash.Error.Changes.InvalidAttribute{}), do: "Invalid"
  defp short_message(%Ash.Error.Query.NotFound{}), do: "Not found"
  defp short_message(%Ash.Error.Forbidden{}), do: "Access denied"
  defp short_message(_), do: "Validation failed"

  defp get_error_field(error) do
    formatter = AshKotlinMultiplatform.output_field_formatter()

    cond do
      Map.has_key?(error, :field) && error.field ->
        FieldFormatter.format_field_name(to_string(error.field), formatter)

      Map.has_key?(error, :fields) && is_list(error.fields) && error.fields != [] ->
        error.fields
        |> Enum.map(&FieldFormatter.format_field_name(to_string(&1), formatter))
        |> Enum.join(", ")

      true ->
        nil
    end
  end
end
