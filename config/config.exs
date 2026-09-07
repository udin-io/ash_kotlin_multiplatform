# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

import Config

# Configure Ash to not validate domain config inclusion in tests
config :ash, :validate_domain_config_inclusion?, false

# Rpc.Runner discovers actions through Ash.Info.domains/1, which reads this key.
# Test-only: shipping a test domain in the library's own app config would be a bug.
if config_env() == :test do
  config :ash_kotlin_multiplatform, ash_domains: [AshKotlinMultiplatform.Test.Domain]
end
