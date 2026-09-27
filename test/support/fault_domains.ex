# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.RaisedErrorsDomain do
  @moduledoc """
  A domain that turns `show_raised_errors?` on, for the redaction tests (#28).

  Kept out of `config :ash_kotlin_multiplatform, ash_domains:` so no other test
  and no codegen gate sees it. A test reaches it by serving an entrypoint that
  names it through `AshKotlinMultiplatform.Test.OverrideManifest`.
  """
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Fault
  end

  kotlin_rpc do
    show_raised_errors? true
  end
end

defmodule AshKotlinMultiplatform.Test.RaisingErrorHandler do
  @moduledoc false
  def handle_error(_error, _context), do: raise("handler bug near password=hunter2")
end

defmodule AshKotlinMultiplatform.Test.FailingHandlerDomain do
  @moduledoc """
  A domain whose `error_handler` raises, for the fail-closed test (#28). Kept
  out of the app config for the reason `RaisedErrorsDomain` gives.
  """
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Fault
  end

  kotlin_rpc do
    error_handler {AshKotlinMultiplatform.Test.RaisingErrorHandler, :handle_error, []}
  end
end
