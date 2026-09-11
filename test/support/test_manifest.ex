# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.Manifest do
  @moduledoc """
  The manifest a consumer would declare, built from this repo's own test domain.

  `config/config.exs` puts `AshKotlinMultiplatform.Test.Domain` into
  `config :ash_kotlin_multiplatform, ash_domains:` in the test environment, so
  `otp_app: :ash_kotlin_multiplatform` here walks exactly that one domain — the
  same path a real consumer's module takes.

  Declared without `:domains` on purpose. That option suppresses the
  `Application.compile_env/3` edge (see `AshKotlinMultiplatform.Manifest`), and
  this module is what the compile-edge tests read.
  """
  use AshKotlinMultiplatform.Manifest, otp_app: :ash_kotlin_multiplatform
end
