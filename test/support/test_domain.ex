# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Domain do
  @moduledoc false
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Author
    resource AshKotlinMultiplatform.Test.Book
    resource AshKotlinMultiplatform.Test.Event
    resource AshKotlinMultiplatform.Test.Secret
    resource AshKotlinMultiplatform.Test.Todo
    resource AshKotlinMultiplatform.Test.User
  end

  kotlin_rpc do
    # Author and Book carry the field-selection coverage: a public relationship,
    # calculation and aggregate, over a data layer that can read back. Secret is
    # published to no rpc_action, so it is reachable only by walking
    # `Author.secrets` — which field selection must refuse.
    resource AshKotlinMultiplatform.Test.Author do
      rpc_action(:list_authors, :read)
      rpc_action(:create_author, :create)

      # Author is the only resource with a data layer, so it is the only one
      # whose destroy, get and keyset reads can be run for real — which is what
      # the round-trip gate needs in order to decode each typed return shape
      # `FunctionCore.determine_return_type/1` can produce (#22).
      rpc_action(:destroy_author, :destroy)
      rpc_action(:get_author, :by_id)
      rpc_action(:keyset_authors, :keyset_paged)

      # The DSL's own single-record options, over the plain `:read` action that
      # knows nothing about them — so what is under test is the wiring, not
      # Ash's `get? true`, which `get_author` above already covers.
      rpc_action :fetch_author, :read do
        get_by [:id]
      end

      # The other half of not-found: a null result rather than an error.
      rpc_action :find_author, :read do
        get_by [:email]
        not_found_error? false
      end
    end

    resource AshKotlinMultiplatform.Test.Book do
      rpc_action(:list_books, :read)
      rpc_action(:create_book, :create)

      # Each of the two read-surface switches on its own, so a test can tell
      # which one dropped which parameter.
      rpc_action :list_books_fixed_order, :read do
        enable_sort?(false)
      end

      rpc_action :list_books_unfiltered, :read do
        enable_filter?(false)
      end
    end

    resource AshKotlinMultiplatform.Test.Event do
      rpc_action(:list_events, :read)
      rpc_action(:create_event, :create)
      rpc_action(:register_event, :register)

      # Exposes one of the action's two metadata fields, so a test can prove a
      # client cannot widen past what the DSL allows.
      rpc_action :register_event_narrow, :register do
        show_metadata([:registered_at])
      end
    end

    resource AshKotlinMultiplatform.Test.Todo do
      rpc_action(:list_todos, :read)
      rpc_action(:get_todo, :read)
      rpc_action(:create_todo, :create)
      rpc_action(:update_todo, :update)
      rpc_action(:destroy_todo, :destroy)
    end

    resource AshKotlinMultiplatform.Test.User do
      rpc_action(:list_users, :read)
      rpc_action(:get_user, :read)
    end
  end
end
