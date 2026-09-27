# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Fault.RefuseByPolicy do
  @moduledoc false
  # No SAT solver is in deps, so `Ash.Policy.Authorizer` cannot run here. The
  # preparation adds the error a refusing policy produces, built the same way,
  # so `policy_breakdown?` follows `config :ash, :policies`.
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, context) do
    Ash.Query.add_error(
      query,
      Ash.Error.Forbidden.Policy.exception(
        actor: context.actor,
        resource: query.resource,
        action: query.action,
        policies: []
      )
    )
  end
end

defmodule AshKotlinMultiplatform.Test.Fault do
  @moduledoc """
  Actions that fail each way an action can fail, for the error redaction tests.

  Every failure carries text a client must never see: a database host, an API
  key, a password, a forbidden field's value. The tests assert that text is
  absent from the encoded response.
  """
  use Ash.Resource,
    domain: AshKotlinMultiplatform.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshKotlinMultiplatform.Resource]

  ets do
    private? true
  end

  kotlin_multiplatform do
    type_name("Fault")
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 3
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title]
    end

    # Raises while the changeset is built, so `validate_action/3` meets it too.
    create :create_raising do
      accept [:title]
      change fn _changeset, _context -> raise "db password=hunter2" end
    end

    read :refused do
      prepare AshKotlinMultiplatform.Test.Fault.RefuseByPolicy
    end

    action :return_string, :string do
      run fn _input, _context ->
        {:error, "Postgrex connection refused host=10.0.0.5 user=app"}
      end
    end

    action :return_term, :string do
      run fn _input, _context ->
        {:error, {:internal_state, %{api_key: "sk_live_123", pid: self()}}}
      end
    end

    action :raise, :string do
      run fn _input, _context -> raise "db password=hunter2" end
    end

    action :hidden_value, :map do
      constraints fields: [hidden: [type: :string]]

      run fn _input, _context ->
        {:ok,
         %{
           hidden: %Ash.ForbiddenField{
             field: :hidden,
             type: :attribute,
             original_value: "s3cret-original"
           }
         }}
      end
    end
  end
end
