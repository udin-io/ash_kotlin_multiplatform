# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

# Resources used by the relationship checks live at the top level: a resource
# defined inside a test body is not fully compiled when the domain that points
# at it is verified, so `Ash.Resource.Info.public_relationships/1` returns
# nothing and the check silently passes.

defmodule AshKotlinMultiplatform.Test.VerifyPublicActions.PrivateReadDestination do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("PrivateReadDestination")
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end
  end
end

defmodule AshKotlinMultiplatform.Test.VerifyPublicActions.PublicReadDestination do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("PublicReadDestination")
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]

    default_accept [:name]
  end
end

defmodule AshKotlinMultiplatform.Test.VerifyPublicActions.PlainDestination do
  @moduledoc false
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key :id
  end

  actions do
    read :read do
      primary? true
      public? false
    end
  end
end

defmodule AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPrivateDestination do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("SourceWithPrivateDestination")
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :destination,
               AshKotlinMultiplatform.Test.VerifyPublicActions.PrivateReadDestination do
      public? true
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPublicDestination do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("SourceWithPublicDestination")
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :destination,
               AshKotlinMultiplatform.Test.VerifyPublicActions.PublicReadDestination do
      public? true
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPlainDestination do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("SourceWithPlainDestination")
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :destination, AshKotlinMultiplatform.Test.VerifyPublicActions.PlainDestination do
      public? true
    end
  end

  actions do
    defaults [:read]
  end
end

defmodule AshKotlinMultiplatform.Test.VerifyPublicActions.MixedActions do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshKotlinMultiplatform.Resource]

  kotlin_multiplatform do
    type_name("MixedActions")
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    default_accept [:name]

    read :read do
      primary? true
    end

    read :internal_lookup do
      public? false
    end

    update :rename do
      accept [:name]
    end
  end
end

defmodule AshKotlinMultiplatform.Rpc.Verifiers.VerifyPublicActionsTest do
  @moduledoc """
  A non-public action must never reach the generated Kotlin client.

  Ash documents `public? false` as "internal-only and must not be exposed by API
  extensions". Before this verifier the generator happily emitted a client
  function for such an action, so the mistake surfaced only as a runtime
  failure — or not at all.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  alias AshKotlinMultiplatform.Test.VerifyPublicActions.MixedActions

  describe "rpc_action" do
    test "rejects an action that is not public?" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyPublicActions.PrivateActionDomain do
            @moduledoc false
            use Ash.Domain,
              extensions: [AshKotlinMultiplatform.Rpc],
              validate_config_inclusion?: false

            resources do
              resource MixedActions
            end

            kotlin_rpc do
              resource MixedActions do
                rpc_action(:lookup, :internal_lookup)
              end
            end
          end
        end

      assert error.message =~ "not `public?`"
      assert error.message =~ "internal_lookup"
      assert error.message =~ "lookup"
    end

    test "accepts an action that is public?" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyPublicActions.PublicActionDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource MixedActions
          end

          kotlin_rpc do
            resource MixedActions do
              rpc_action(:list, :read)
            end
          end
        end
      end
    end

    test "rejects a read_action that is not public?" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyPublicActions.PrivateReadActionDomain do
            @moduledoc false
            use Ash.Domain,
              extensions: [AshKotlinMultiplatform.Rpc],
              validate_config_inclusion?: false

            resources do
              resource MixedActions
            end

            kotlin_rpc do
              resource MixedActions do
                rpc_action :rename, :rename do
                  read_action :internal_lookup
                end
              end
            end
          end
        end

      assert error.message =~ "not `public?`"
      assert error.message =~ "internal_lookup"
      assert error.message =~ "read_action"
    end
  end

  describe "typed_query" do
    test "rejects an action that is not public?" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyPublicActions.PrivateTypedQueryDomain do
            @moduledoc false
            use Ash.Domain,
              extensions: [AshKotlinMultiplatform.Rpc],
              validate_config_inclusion?: false

            resources do
              resource MixedActions
            end

            kotlin_rpc do
              resource MixedActions do
                typed_query :names, :internal_lookup do
                  fields(["id", "name"])
                  kotlin_result_type_name("NamesResult")
                  kotlin_fields_const_name("NAMES_FIELDS")
                end
              end
            end
          end
        end

      assert error.message =~ "not `public?`"
      assert error.message =~ "internal_lookup"
      assert error.message =~ "names"
    end
  end

  describe "relationship read actions" do
    test "rejects a public relationship whose destination read action is not public?" do
      error =
        assert_dsl_error do
          defmodule Elixir.AshKotlinMultiplatform.Test.VerifyPublicActions.PrivateRelDomain do
            @moduledoc false
            use Ash.Domain,
              extensions: [AshKotlinMultiplatform.Rpc],
              validate_config_inclusion?: false

            resources do
              resource AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPrivateDestination
              resource AshKotlinMultiplatform.Test.VerifyPublicActions.PrivateReadDestination
            end

            kotlin_rpc do
              resource AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPrivateDestination do
                rpc_action(:list, :read)
              end
            end
          end
        end

      assert error.message =~ "not `public?`"
      assert error.message =~ "destination"
      assert error.message =~ "PrivateReadDestination"
    end

    test "accepts a public relationship whose destination read action is public?" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyPublicActions.PublicRelDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPublicDestination
            resource AshKotlinMultiplatform.Test.VerifyPublicActions.PublicReadDestination
          end

          kotlin_rpc do
            resource AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPublicDestination do
              rpc_action(:list, :read)
            end
          end
        end
      end
    end

    test "ignores a destination that is not a Kotlin resource" do
      refute_dsl_errors do
        defmodule Elixir.AshKotlinMultiplatform.Test.VerifyPublicActions.PlainRelDomain do
          @moduledoc false
          use Ash.Domain,
            extensions: [AshKotlinMultiplatform.Rpc],
            validate_config_inclusion?: false

          resources do
            resource AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPlainDestination
            resource AshKotlinMultiplatform.Test.VerifyPublicActions.PlainDestination
          end

          kotlin_rpc do
            resource AshKotlinMultiplatform.Test.VerifyPublicActions.SourceWithPlainDestination do
              rpc_action(:list, :read)
            end
          end
        end
      end
    end
  end
end
