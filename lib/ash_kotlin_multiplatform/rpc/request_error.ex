# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Rpc.RequestError do
  @moduledoc false
  # Carries an already-worded request error (`action_not_found`, a getBy
  # check, a refused `filter`) through `AshIntrospection.Rpc.Errors.to_errors/6`,
  # so a resource's `handle_rpc_error/2` and the domain's `error_handler` see it
  # like any other error. Class `:invalid`, because `Ash.Error.to_error_class/1`
  # turns any exception outside an Ash class into an `UnknownError`, which the
  # core words as "Something went wrong".
  use Splode.Error, fields: [:error], class: :invalid

  def message(%{error: error}), do: error.message
end

defimpl AshIntrospection.Rpc.Error, for: AshKotlinMultiplatform.Rpc.RequestError do
  def to_error(%{error: error}), do: error
end
