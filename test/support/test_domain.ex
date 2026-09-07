# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Domain do
  @moduledoc false
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Event
    resource AshKotlinMultiplatform.Test.Todo
    resource AshKotlinMultiplatform.Test.User
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.Event do
      rpc_action :list_events, :read
      rpc_action :create_event, :create
      rpc_action :register_event, :register
    end

    resource AshKotlinMultiplatform.Test.Todo do
      rpc_action :list_todos, :read
      rpc_action :get_todo, :read
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy
    end

    resource AshKotlinMultiplatform.Test.User do
      rpc_action :list_users, :read
      rpc_action :get_user, :read
    end
  end
end
