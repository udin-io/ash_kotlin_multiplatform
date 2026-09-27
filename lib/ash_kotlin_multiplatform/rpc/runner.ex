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

  require Logger

  alias AshKotlinMultiplatform.Manifest
  alias AshKotlinMultiplatform.Manifest.Entrypoints
  alias AshKotlinMultiplatform.Resource.Info, as: ResourceInfo
  alias AshKotlinMultiplatform.Rpc.KeyNames
  alias AshKotlinMultiplatform.Rpc.Pipeline
  alias AshIntrospection.ErrorFormatter
  alias AshIntrospection.Rpc.ErrorBuilder
  alias AshIntrospection.Rpc.Errors
  alias AshIntrospection.Rpc.FieldProcessing.FieldSelector
  alias AshIntrospection.Rpc.Request
  alias AshIntrospection.FieldFormatter
  alias AshIntrospection.ResourceInfo, as: SharedResourceInfo

  # Every option `Ash.Page.Keyset` and `Ash.Page.Offset` declare
  # (`deps/ash/lib/ash/page/keyset.ex:43`, `deps/ash/lib/ash/page/offset.ex:34`).
  # `RunnerKeyTypeTest` fails when an Ash upgrade moves them.
  @page_option_names [:after, :before, :count, :filter, :limit, :offset]

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
        error_response(reason, %{})
    end
  end

  @doc """
  Validate an RPC action without executing it.

  Useful for real-time validation in client applications. Takes `:actor`,
  `:tenant` and `:context` as `run_action/3` does; `:context` reaches the
  error handlers only.
  """
  def validate_action(otp_app, params, opts \\ []) do
    action_name = params["action"]
    actor = Keyword.get(opts, :actor)
    tenant = Keyword.get(opts, :tenant)
    context = Keyword.get(opts, :context, %{})

    case discover_action(otp_app, action_name) do
      {:ok, {domain, resource, rpc_action}} ->
        validate_changeset(domain, resource, rpc_action, params, actor, tenant, context)

      {:error, reason} ->
        error_response(reason, %{})
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
        error_response(error, target(domain, resource, rpc_action, context))
    end
  rescue
    exception ->
      error_response(exception, target(domain, resource, rpc_action, context), __STACKTRACE__)
  catch
    kind, reason ->
      error_response(
        {kind, reason},
        target(domain, resource, rpc_action, context),
        __STACKTRACE__
      )
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
    input = parse_input(params, resource, action.name, config)
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

  defp validate_changeset(domain, resource, rpc_action, params, actor, tenant, context) do
    config = Pipeline.request_config(rpc_action)
    action_name = rpc_action.action
    action_info = SharedResourceInfo.action(resource, action_name, config)
    input = parse_input(params, resource, action_name, config)

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
        build_validation_error_response(errors, target(domain, resource, rpc_action, context))

      {:error, error} ->
        error_response(error, target(domain, resource, rpc_action, context))
    end
  rescue
    exception ->
      error_response(exception, target(domain, resource, rpc_action, context), __STACKTRACE__)
  catch
    kind, reason ->
      error_response(
        {kind, reason},
        target(domain, resource, rpc_action, context),
        __STACKTRACE__
      )
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
    sent = normalize_get_by(params["getBy"], resource, config, allowed)

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

  # `allowed` is the DSL's list of atoms and the filter below is built from it,
  # so the fields the DSL named come back as those atoms and anything else
  # stays the string the client sent — which is what `extra` reports.
  defp normalize_get_by(get_by, resource, config, allowed) when is_map(get_by) do
    get_by
    |> KeyNames.parse(resource, config)
    |> KeyNames.resolve(allowed)
  end

  defp normalize_get_by(_, _resource, _config, _allowed), do: %{}

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

  defp parse_input(params, resource, action_name, config) do
    input = params["input"] || %{}
    KeyNames.parse_input(input, resource, action_name, config)
  end

  # `AshIntrospection.Rpc.Pipeline` matches an identity map against the
  # resource's own attribute atoms — `Map.has_key?(identity, :id)`, then
  # `Map.fetch!/2` on the same atom
  # (`deps/ash_introspection/lib/ash_introspection/rpc/pipeline.ex:629`) — so
  # the keys that name an attribute have to arrive as those atoms. The names
  # come from the resource, never from whatever the VM has interned (#77). A
  # key naming no attribute stays a string, which no identity matches, and the
  # pipeline answers `invalid_identity` listing what was sent.
  defp parse_identity(params, resource, config) do
    case params["identity"] do
      nil ->
        nil

      id when is_binary(id) ->
        id

      id when is_map(id) ->
        id
        |> KeyNames.parse(resource, config)
        |> KeyNames.resolve(attribute_names(resource, config))

      id ->
        id
    end
  end

  defp attribute_names(resource, config) do
    resource
    |> SharedResourceInfo.attributes(config)
    |> Enum.map(& &1.name)
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

  # `Ash.Page.page_opts/1` reads `page[:after]` and `page[:offset]` to pick the
  # keyset or offset schema and then validates the result with `Spark.Options`,
  # so pagination is the one parsed map that must carry atoms
  # (`deps/ash/lib/ash/page/page.ex:17`). A key naming no page option stays a
  # string and Ash rejects it, which is what it did before — the difference is
  # that the shape no longer turns on what the VM has interned (#77).
  #
  # ash 3.33.10 added a guard that rejects the whole `page` term up front
  # unless it is already a list (`deps/ash/lib/ash/page/page.ex:16`), before
  # `resolve/2`'s map ever reaches the option-by-option validation above. A
  # map with only known names is still a valid page, so it becomes a keyword
  # list to clear that guard. A map holding an unresolved (string) key stays a
  # map on purpose: `Ash.Error.Query.InvalidPage` inspects whatever it is
  # handed verbatim (`deps/ash/lib/ash/error/query/invalid_page.ex:10`), and
  # `RunnerKeyTypeTest` pins that an unknown key's error message reads back
  # the client's own map shape, `"key" => value`, not a list of tuples
  # (issue #116).
  defp parse_pagination(params, config) do
    case params["page"] do
      nil ->
        nil

      page ->
        resolved =
          page
          |> KeyNames.parse(nil, config)
          |> KeyNames.resolve(@page_option_names)

        if Enum.all?(Map.keys(resolved), &is_atom/1) do
          Map.to_list(resolved)
        else
          resolved
        end
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

  # `success` is true because the validation ran; `valid` carries the answer.
  # The errors take the same path as a failed action's.
  defp build_validation_error_response(errors, target) do
    %{"errors" => client_errors} = error_response(errors, target)

    %{"success" => true, "valid" => false, "errors" => client_errors}
  end

  # What an error is about: the domain, resource and action it came from, and
  # the caller's context. Empty before an action is found.
  defp target(domain, resource, rpc_action, context),
    do: %{domain: domain, resource: resource, action: rpc_action.action, context: context}

  # Reasons this library and the core pipeline return while reading the
  # request. `ErrorBuilder` words each one, with a field path and a suggestion
  # the client can act on. The list is closed on purpose: `ErrorBuilder`'s
  # fallback for a tuple it does not know puts `inspect/1` of it in `details`,
  # so any other tuple goes to `Errors.to_errors/6` instead.
  @request_reasons [
    :action_not_found,
    :missing_required_parameter,
    :invalid_fields,
    :missing_get_by_fields,
    :unexpected_get_by_fields,
    :invalid_get_by,
    :identity_not_supported,
    :missing_identity,
    :invalid_identity
  ]

  # Every failure reaches the client through here. A request reason is worded
  # below. Anything else goes through `Errors.to_errors/6`, which words each
  # error by the `AshIntrospection.Rpc.Error` protocol: an error with no
  # implementation, a bare string or any other term becomes "Something went
  # wrong", so internal detail stays on the server log.
  # A raise, throw or exit inside an action comes here too, with its
  # stacktrace: a failed result like any other, never a 500 (decision 3 on
  # #123).
  defp error_response(error, target, stacktrace \\ []) do
    errors = client_errors(error, target)

    log_hidden_detail(errors, error, target, stacktrace)

    %{"success" => false, "errors" => errors}
  end

  # The last resort. An error handler is consumer code: one that returns a
  # string or a struct makes the core or `to_client/1` raise, and a raise here
  # would escape as a 500, since the caller's `rescue` lands back in this
  # function. So a failure while shaping errors answers a static
  # `internal_error` that runs no handler.
  defp client_errors(error, target) do
    error |> error_maps(target) |> Enum.map(&to_client/1)
  rescue
    failure -> [shaping_failure(Exception.format(:error, failure, __STACKTRACE__))]
  catch
    kind, reason -> [shaping_failure(Exception.format(kind, reason, __STACKTRACE__))]
  end

  defp shaping_failure(failure) do
    uuid = Ash.UUID.generate()

    Logger.error("""
    Shaping an RPC error failed; the client got internal_error (error id #{uuid}).
    #{failure}
    """)

    %{
      "type" => "internal_error",
      "message" => "Something went wrong. Unique error id: #{uuid}",
      "shortMessage" => "Internal error",
      "vars" => %{},
      "fields" => [],
      "field" => nil,
      "path" => [],
      "errorId" => uuid
    }
  end

  # The core has no reason for a read-surface switch or for validating an
  # action that is not a create or update, so these two are worded here, in
  # the core's shape.
  defp error_maps({:filter_not_supported, rpc_action_name}, _target),
    do: [unsupported_read_parameter("filter", rpc_action_name, "enable_filter?")]

  defp error_maps({:sort_not_supported, rpc_action_name}, _target),
    do: [unsupported_read_parameter("sort", rpc_action_name, "enable_sort?")]

  defp error_maps(:validation_not_supported, _target) do
    [
      %{
        type: "unsupported",
        message: "Validation is only supported for create and update actions",
        short_message: "Unsupported",
        vars: %{},
        fields: [],
        path: []
      }
    ]
  end

  defp error_maps(reason, _target)
       when is_tuple(reason) and tuple_size(reason) > 1 and elem(reason, 0) in @request_reasons do
    reason
    |> ErrorBuilder.build_error_response(Pipeline.build_config())
    |> List.wrap()
  end

  defp error_maps(error, target) do
    Errors.to_errors(
      without_bread_crumbs(error),
      target[:domain],
      target[:resource],
      target[:action],
      Map.get(target, :context, %{}),
      Pipeline.build_config()
    )
  end

  # Splode prefixes `Exception.message/1` with the bread crumbs Ash leaves on an
  # error ("Error returned from: MyApp.Post.create"), and several core
  # `Rpc.Error` impls send that message, so the module name would reach the
  # client. The log keeps them: `log_hidden_detail/4` gets the original error.
  defp without_bread_crumbs(error) when is_list(error),
    do: Enum.map(error, &without_bread_crumbs/1)

  defp without_bread_crumbs(%{errors: errors} = error) when is_list(errors),
    do: %{drop_bread_crumbs(error) | errors: Enum.map(errors, &without_bread_crumbs/1)}

  defp without_bread_crumbs(error), do: drop_bread_crumbs(error)

  defp drop_bread_crumbs(%{bread_crumbs: _} = error), do: %{error | bread_crumbs: []}
  defp drop_bread_crumbs(error), do: error

  # The client got "Something went wrong" in place of this error, so the log is
  # the only place its text survives. An `internal_error` carries the id the
  # client was given, so the two ends can be joined.
  defp log_hidden_detail(errors, error, target, stacktrace) do
    case Enum.find(errors, &(&1["type"] in ["unknown_error", "internal_error"])) do
      nil ->
        :ok

      hidden ->
        Logger.error("""
        RPC action #{inspect(target[:action])} on #{inspect(target[:resource])} failed; \
        the client got #{hidden["type"]}#{if id = hidden["errorId"], do: " (error id #{id})"}.
        #{format_for_log(error, stacktrace)}
        """)
    end
  end

  # A throw or an exit is caught as `{kind, reason}`, which the core treats as
  # any other term: "Something went wrong".
  defp format_for_log({kind, reason}, stacktrace) when kind in [:throw, :exit],
    do: Exception.format(kind, reason, stacktrace)

  defp format_for_log(error, stacktrace) when is_exception(error),
    do: Exception.format(:error, error, stacktrace)

  defp format_for_log(error, _stacktrace), do: inspect(error)

  # `:camel_case` is pinned rather than read from `output_field_formatter`:
  # the Kotlin and Swift clients read `shortMessage` whatever that setting is
  # (#24). Issue 57 decides whether error keys follow it.
  #
  # `message` arrives as finished text, with `vars` beside it for an app that
  # translates. `field` repeats the first of `fields` for the Swift client.
  defp to_client(error) do
    client = ErrorFormatter.format(error, :camel_case)
    vars = Map.get(client, "vars") || %{}
    fields = Enum.map(Map.get(client, "fields") || [], &to_string/1)

    client
    |> Map.put("message", render_message(client["message"], vars))
    |> Map.put("fields", fields)
    |> Map.put("field", List.first(fields))
    |> Map.put("path", Enum.map(Map.get(client, "path") || [], &path_segment/1))
  end

  # `ErrorBuilder` leaves path segments as atoms; `Errors.to_errors/6` has
  # already turned them into strings. A list index stays a number.
  defp path_segment(segment) when is_atom(segment), do: Atom.to_string(segment)
  defp path_segment(segment), do: segment

  defp render_message(message, vars) when is_binary(message) and is_map(vars) do
    Enum.reduce(vars, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", render_value(value))
    end)
  end

  defp render_message(message, _vars), do: message

  defp render_value(value) when is_list(value), do: Enum.map_join(value, ", ", &render_value/1)
  defp render_value(value) when is_binary(value), do: value
  defp render_value(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp render_value(value), do: inspect(value)

  defp unsupported_read_parameter(parameter, rpc_action_name, dsl_option) do
    %{
      type: "#{parameter}_not_supported",
      message:
        "RPC action '#{rpc_action_name}' does not accept '#{parameter}'. " <>
          "Set `#{dsl_option} true` on the rpc_action to enable it, or regenerate the client.",
      short_message: "#{String.capitalize(parameter)} not supported",
      vars: %{},
      fields: [],
      path: []
    }
  end
end
