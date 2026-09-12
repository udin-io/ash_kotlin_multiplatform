# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

defmodule AshKotlinMultiplatform.Test.ScopedDomain do
  @moduledoc """
  A second domain, deliberately absent from `config :ash_kotlin_multiplatform,
  ash_domains:`, carrying the one DSL entry the main test domain does not: a
  `typed_query`.

  It is kept out of the app config because the Kotlin compile and round-trip
  gates emit everything the main domain declares, and a `typed_query` has no
  end-to-end codegen coverage yet. Scoping it here tests the manifest half
  without asking the codegen half to grow a feature.
  """
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Book
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.Book do
      rpc_action :scoped_list_books, :read

      typed_query :book_titles, :read,
        fields: ["id", "title"],
        kotlin_result_type_name: "BookTitlesResult",
        kotlin_fields_const_name: "BOOK_TITLES_FIELDS"
    end
  end
end

defmodule AshKotlinMultiplatform.Test.ScopedManifest do
  @moduledoc """
  A manifest built from exactly one domain, through the `:domains` option.

  Exercises both the option and the `typed_query` half of the entrypoint
  mapping. Because `:domains` is given, this module carries no
  `Application.compile_env/3` edge — which is itself asserted, so the
  documented cost of the option stays true.
  """
  use AshKotlinMultiplatform.Manifest,
    otp_app: :ash_kotlin_multiplatform,
    domains: [AshKotlinMultiplatform.Test.ScopedDomain]
end
