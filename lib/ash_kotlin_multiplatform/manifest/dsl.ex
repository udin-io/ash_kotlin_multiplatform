# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Manifest.Dsl do
  @moduledoc false

  use Spark.Dsl.Extension,
    transformers: [
      AshKotlinMultiplatform.Manifest.Transformers.BuildManifest,
      AshKotlinMultiplatform.Manifest.Transformers.DecorateManifest
    ]
end
