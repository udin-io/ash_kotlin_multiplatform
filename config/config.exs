# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

import Config

# Configure Ash to not validate domain config inclusion in tests
config :ash, :validate_domain_config_inclusion?, false

# ash 3.33.0 refuses to compile a resource until the host states how string
# length is counted (Ash.Resource.Transformers.RequireStringLengthCountConfig).
# :codepoints matches how SQL data layers count, so a max_length bounds the
# stored value. This applies to the resources compiled in THIS repo only:
# config/ is not in the package files list, so consumers still choose for
# themselves.
config :ash, default_string_length_count: :codepoints

# Rpc.Runner discovers actions through Ash.Info.domains/1, which reads this key.
# Test-only: shipping a test domain in the library's own app config would be a bug.
if config_env() == :test do
  config :ash_kotlin_multiplatform, ash_domains: [AshKotlinMultiplatform.Test.Domain]

  # The ETS data layer logs every write at :debug, which buries the test output.
  config :logger, level: :warning
end
