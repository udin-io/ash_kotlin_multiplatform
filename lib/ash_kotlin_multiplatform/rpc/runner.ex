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
  - `"fields"` - Fields to select/return (sparse fieldsets)
  - `"identity"` - Identity for update/destroy actions
  - `"filter"` - Filter for read actions
  - `"sort"` - Sort string for read actions
  - `"page"` - Pagination options

  ## Response Format

  Returns a map with:
  - `"success"` - Boolean indicating success
  - `"data"` - The action result (on success)
  - `"errors"` - List of error objects (on failure)
  - `"metadata"` - Optional metadata from the action
  """

  alias AshKotlinMultiplatform.Rpc.Info
  alias AshKotlinMultiplatform.Rpc.Pipeline
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
    action_info = Ash.Resource.Info.action(resource, action_name)

    # Build the request
    request = build_request(domain, resource, action_info, rpc_action, params, actor, tenant, context)

    # Execute through the pipeline
    with {:ok, ash_result} <- Pipeline.execute_ash_action(request),
         {:ok, processed} <- Pipeline.process_result(ash_result, request) do
      # Use format_output/1 which just formats field names without expecting a wrapped response
      formatted = Pipeline.format_output(processed)
      build_success_response(formatted)
    else
      {:error, error} ->
        build_error_response(error)
    end
  end

  defp build_request(domain, resource, action, rpc_action, params, actor, tenant, context) do
    input = parse_input(params)
    fields = params["fields"] || []
    identity = parse_identity(params)
    filter = parse_filter(params)
    sort = parse_sort(params)
    page = parse_pagination(params)

    # Build extraction template for field selection
    extraction_template = build_extraction_template(resource, fields)
    {select, load} = build_select_and_load(resource, fields)

    # Get show_metadata, ensuring it's always a list
    # nil in DSL means "show all", but for the pipeline we need a list
    # false or [] means "show none", a list means "show specific fields"
    show_metadata =
      case Map.get(rpc_action, :show_metadata) do
        nil ->
          # nil means "show all" - get all metadata fields from action
          get_action_metadata_fields(action)
        false -> []
        list when is_list(list) -> list
        _ -> []
      end

    %Request{
      domain: domain,
      resource: resource,
      action: action,
      rpc_action: rpc_action,
      input: input,
      identity: identity,
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
    }
  end

  defp validate_changeset(domain, resource, rpc_action, params, actor, tenant) do
    action_name = rpc_action.action
    action_info = Ash.Resource.Info.action(resource, action_name)
    input = parse_input(params)

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
          identity = parse_identity(params)
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
        %{"success" => false, "errors" => [%{
          "type" => "unsupported",
          "message" => "Validation is only supported for create and update actions",
          "shortMessage" => "Unsupported"
        }]}

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

  # Get all metadata field names from an action
  defp get_action_metadata_fields(action) do
    case Map.get(action, :metadata) do
      nil -> []
      metadata when is_list(metadata) ->
        Enum.map(metadata, fn
          %{name: name} -> name
          {name, _} -> name
          name when is_atom(name) -> name
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Input Parsing
  # ---------------------------------------------------------------------------

  defp parse_input(params) do
    input = params["input"] || %{}
    convert_keys_to_atoms(input)
  end

  defp parse_identity(params) do
    case params["identity"] do
      nil -> nil
      id when is_binary(id) -> id
      id when is_map(id) -> convert_keys_to_atoms(id)
      id -> id
    end
  end

  defp parse_filter(params) do
    case params["filter"] do
      nil -> nil
      filter -> convert_keys_to_atoms(filter)
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
      page -> convert_keys_to_atoms(page)
    end
  end

  defp convert_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        atom_key = to_snake_case_atom(key)
        {atom_key, convert_keys_to_atoms(value)}

      {key, value} ->
        {key, convert_keys_to_atoms(value)}
    end)
  end

  defp convert_keys_to_atoms(list) when is_list(list) do
    Enum.map(list, &convert_keys_to_atoms/1)
  end

  defp convert_keys_to_atoms(value), do: value

  defp to_snake_case_atom(string) when is_binary(string) do
    string
    |> String.replace(~r/([a-z])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.to_atom()
  end

  # ---------------------------------------------------------------------------
  # Field Selection
  # ---------------------------------------------------------------------------

  defp build_extraction_template(resource, []), do: build_default_extraction_template(resource)

  defp build_extraction_template(_resource, fields) when is_list(fields) do
    Enum.map(fields, fn field ->
      atom_field = to_snake_case_atom(field)
      {atom_field, []}
    end)
  end

  defp build_default_extraction_template(resource) do
    attributes = Ash.Resource.Info.public_attributes(resource)

    Enum.map(attributes, fn attr ->
      {attr.name, []}
    end)
  end

  defp build_select_and_load(resource, []) do
    attributes = Ash.Resource.Info.public_attributes(resource)
    select = Enum.map(attributes, & &1.name)
    {select, []}
  end

  defp build_select_and_load(resource, fields) when is_list(fields) do
    attribute_names =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map(& &1.name)

    relationship_names =
      try do
        resource
        |> Ash.Resource.Info.public_relationships()
        |> Enum.map(& &1.name)
      rescue
        _ -> []
      end

    {select, load} =
      Enum.reduce(fields, {[], []}, fn field, {sel, lod} ->
        atom_field = to_snake_case_atom(field)

        cond do
          atom_field in attribute_names ->
            {[atom_field | sel], lod}

          atom_field in relationship_names ->
            {sel, [atom_field | lod]}

          true ->
            {sel, lod}
        end
      end)

    {Enum.reverse(select), Enum.reverse(load)}
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
