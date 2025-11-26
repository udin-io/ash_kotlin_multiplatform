# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

import Config

# Configure Ash to not validate domain config inclusion in tests
config :ash, :validate_domain_config_inclusion?, false
