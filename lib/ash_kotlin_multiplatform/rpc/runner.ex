# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.Runner do
  @moduledoc """
  RPC action runner for Kotlin client requests.

  This module handles discovering and executing RPC actions configured via
  the `kotlin_rpc` DSL extension. It provides a standard interface for
  processing requests from Kotlin clients.

  ## The manifest answers, not live introspection

  Since `ash_introspection#23` stage 5a an `rpc_action` name is resolved
  against the manifest's `:rpc_action_lookup`
  (`AshKotlinMultiplatform.Manifest.rpc_action_lookup/1`), and every read of a
  resource's actions and attributes goes through
  `AshIntrospection.ResourceInfo` with
  `AshKotlinMultiplatform.Rpc.Pipeline.request_config/1`. A request therefore
  answers from what code generation emitted, which is what the generated client
  was built against.

  Two consequences. `config :ash_kotlin_multiplatform, manifest:` has to name a
  current manifest module for requests, not only for code generation: an
  `rpc_action` the manifest does not carry is `action_not_found`. And `otp_app`
  selects nothing here — that config key names one module for the library, and
  the module names its own otp_app.

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
    returns every public attribute and nothing else. For a generic action
    those are the attributes of the resource it returns, not the one that owns
    it, or the declared fields of a map, struct, keyword list or tuple it
    returns. Selection is resolved by
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

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Manifest.Entrypoints
  alias AshKotlinMultiplatform.Resource.Info, as: ResourceInfo
  alias AshKotlinMultiplatform.Rpc.KeyNames
  alias AshKotlinMultiplatform.Rpc.Pipeline
  alias AshIntrospection.Rpc.ErrorBuilder
  alias AshIntrospection.Rpc.FieldProcessing.FieldSelector
  alias AshIntrospection.Rpc.Request
  alias AshIntrospection.FieldFormatter
  alias AshIntrospection.ResourceInfo, as: SharedResourceInfo

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

  # The manifest's `:rpc_action_lookup` is the answer, not a scan of
  # `Ash.Info.domains/1`. Both are built from the same `kotlin_rpc` blocks, so
  # they agree when the manifest is current — and when they disagree, the
  # manifest is what code generation emitted, so it is the one the client was
  # built against. Scanning live meant a request could reach an action no
  # generated function names, and a stale manifest went on answering with
  # nothing comparing the two (`ash_introspection#23` stage 5a).
  #
  # `otp_app` no longer selects anything. `config :ash_kotlin_multiplatform,
  # manifest:` names one module for the library, and that module names its own
  # otp_app; see `AshKotlinMultiplatform.Manifest` on why the manifest is
  # app-wide. The parameter stays because `run_action/3` and `validate_action/3`
  # are the public entry points and a consumer's call sites carry it.
  defp discover_action(_otp_app, action_name) when is_binary(action_name) do
    case Map.fetch(Manifest.rpc_action_lookup(), action_name) do
      {:ok, entrypoint} -> {:ok, entrypoint_target(entrypoint)}
      :error -> {:error, {:action_not_found, action_name}}
    end
  end

  defp discover_action(_otp_app, _), do: {:error, {:missing_required_parameter, :action}}

  # `Manifest.Entrypoints.entry/5` writes the domain and the `rpc_action` struct
  # into the entrypoint's `config` under this library's namespace, because
  # `%Ash.Info.Manifest.Entrypoint{}` carries a resource and an action and
  # nothing else. The DSL struct comes back whole, so every `rpc_action` option
  # below reads the same way it did off the live scan.
  defp entrypoint_target(%Ash.Info.Manifest.Entrypoint{resource: resource, config: config}) do
    %{domain: domain, rpc_action: rpc_action} = Map.fetch!(config, Entrypoints.namespace())
    {domain, resource, rpc_action}
  end

  # ---------------------------------------------------------------------------
  # Action Execution
  # ---------------------------------------------------------------------------

  defp execute_action(domain, resource, rpc_action, params, actor, tenant, context) do
    config = Pipeline.request_config(rpc_action)
    action_name = rpc_action.action

    action_info =
      resource
      |> SharedResourceInfo.action(action_name, config)
      |> apply_get?(rpc_action)

    with {:ok, request} <-
           build_request(
             domain,
             resource,
             action_info,
             rpc_action,
             params,
             actor,
             tenant,
             context,
             config
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

  defp build_request(
         domain,
         resource,
         action,
         rpc_action,
         params,
         actor,
         tenant,
         context,
         config
       ) do
    input = parse_input(params, resource, config)
    fields = params["fields"] || []
    identity = parse_identity(params, resource, config)
    filter = parse_filter(params, resource, config)
    sort = parse_sort(params)
    page = parse_pagination(params, config)

    show_metadata =
      action
      |> dsl_metadata_fields(rpc_action)
      |> narrow_metadata_fields(parse_metadata_fields(params))

    with :ok <- check_read_surface(rpc_action, filter, sort),
         {:ok, get_by} <- parse_get_by(params, rpc_action, resource, config),
         {:ok, {select, load, extraction_template}} <-
           select_fields(resource, action, fields, config) do
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
    config = Pipeline.request_config(rpc_action)
    action_name = rpc_action.action
    action_info = SharedResourceInfo.action(resource, action_name, config)
    input = parse_input(params, resource, config)

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
          identity = parse_identity(params, resource, config)

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
  #
  # No action-type guard here on purpose. `Rpc.Verifiers.VerifyIdentities`
  # refuses to compile a `get_by` on anything but a read (#69), so on a create,
  # update or destroy `allowed` is the schema default `[]` and this returns
  # `{:ok, nil}`. A guard would be a branch no test can reach without disabling
  # the verifier.
  defp parse_get_by(params, rpc_action, resource, config) do
    allowed = configured_get_by(rpc_action)
    sent = normalize_get_by(params["getBy"], resource, config)

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

  defp normalize_get_by(get_by, resource, config) when is_map(get_by),
    do: KeyNames.parse(get_by, resource, config)

  defp normalize_get_by(_, _resource, _config), do: %{}

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

  defp parse_input(params, resource, config) do
    input = params["input"] || %{}
    KeyNames.parse(input, resource, config)
  end

  defp parse_identity(params, resource, config) do
    case params["identity"] do
      nil -> nil
      id when is_binary(id) -> id
      id when is_map(id) -> KeyNames.parse(id, resource, config)
      id -> id
    end
  end

  defp parse_filter(params, resource, config) do
    case params["filter"] do
      nil -> nil
      filter -> KeyNames.parse(filter, resource, config)
    end
  end

  defp parse_sort(params) do
    case params["sort"] do
      nil -> nil
      sort when is_binary(sort) -> Pipeline.format_sort_string(sort)
      sort -> sort
    end
  end

  defp parse_pagination(params, config) do
    case params["page"] do
      nil -> nil
      page -> KeyNames.parse(page, nil, config)
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
    [name |> KeyNames.snake_case() |> String.to_existing_atom()]
  rescue
    ArgumentError -> []
  end

  defp existing_metadata_atom(name) when is_atom(name) and not is_nil(name), do: [name]
  defp existing_metadata_atom(_), do: []

  # ---------------------------------------------------------------------------
  # Field Selection
  # ---------------------------------------------------------------------------

  # An empty request gets every public attribute of the resource the action
  # produces: no relationships, calculations or aggregates. The client asked
  # for nothing in particular, so it gets that resource's own flat shape.
  #
  # For a generic action that is the resource it RETURNS, never the one that
  # owns it. `Book.summarize` returns `Summary`, and taking Book's attributes
  # copied five nil keys out of a Summary, which generated Kotlin decoded as
  # `Summary(label=null)` with no error (#88). A generic action returning a map,
  # struct, keyword list or tuple that declares its `fields` gets those fields,
  # for the same reason (#88, #95).
  #
  # A union return gets an EMPTY template, which is the one case the runner
  # cannot fill in: which member is active is decided at result time by
  # `%Ash.Union{type:}`, and the same action can answer with a different one
  # each call. `ResultProcessor.extract_union_value/4` reads an empty template
  # as "this member's declared fields", so the member gets exactly what #88 and
  # #95 give its type (#96).
  #
  # Any other generic return keeps the owner's attributes, as before #88. The
  # shared pipeline ignores that template for an untyped map and a scalar.
  defp select_fields(resource, action, [], config) do
    {:ok, default_selection(resource, action, config)}
  end

  defp select_fields(resource, action, fields, config) when is_list(fields) do
    case FieldSelector.process(resource, action.name, fields, field_selector_config(config)) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:invalid_fields, reason}}
    end
  end

  defp select_fields(_resource, _action, fields, _config) do
    {:error, {:invalid_fields, {:fields_must_be_a_list, fields}}}
  end

  defp default_selection(resource, %{type: :action} = action, config) do
    case ResourceInfo.returned_resource(action) do
      nil -> map_field_selection(ResourceInfo.returned_type(action), resource, config)
      returned -> attribute_selection(returned, config)
    end
  end

  defp default_selection(resource, _action, config), do: attribute_selection(resource, config)

  # A tuple has no keys, so its template names each field by position. That is
  # the template `FieldSelector` builds for an empty request, so it is taken
  # from there rather than rebuilt.
  defp map_field_selection({Ash.Type.Tuple, constraints}, resource, config) do
    case Keyword.get(constraints, :fields) do
      [_ | _] ->
        FieldSelector.select_tuple_fields(constraints, [], [], field_selector_config(config))

      _untyped ->
        attribute_selection(resource, config)
    end
  end

  defp map_field_selection({type, constraints}, resource, config)
       when type in [Ash.Type.Map, Ash.Type.Struct, Ash.Type.Keyword] do
    case Keyword.get(constraints, :fields) do
      [_ | _] = fields -> {[], [], Keyword.keys(fields)}
      _untyped -> attribute_selection(resource, config)
    end
  end

  # No select and no load: a generic action reads nothing from a data layer, and
  # an empty template is what makes the active member choose its own fields.
  # Sending Book's attribute names here is what returned `nil` for a single
  # union and `[]` for a list, whatever the member was (#96).
  defp map_field_selection({Ash.Type.Union, _constraints}, _resource, _config), do: {[], [], []}

  defp map_field_selection(_other_return, resource, config),
    do: attribute_selection(resource, config)

  defp attribute_selection(resource, config) do
    template = Enum.map(SharedResourceInfo.public_attributes(resource, config), & &1.name)
    {template, [], template}
  end

  # `is_interop_resource?` is what stops a nested request walking out of the
  # published graph: without it `FieldSelector` treats every Ash resource as
  # traversable, so a relationship to a resource the `kotlin_rpc` DSL never
  # exposed would become readable the moment nested selection started working.
  #
  # `config` is the request config, so the manifest rides in with it. Building
  # from `Pipeline.build_config/0` here is what kept every nested field
  # classification on live introspection.
  defp field_selector_config(config) do
    Map.put(
      config,
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
