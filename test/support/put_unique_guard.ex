# SPDX-FileCopyrightText: 2025 ash_kotlin_multiplatform contributors
#
# SPDX-License-Identifier: MIT

# Fixtures for #33 rows 7 and 10: `DecorateManifest.put_unique/4` already
# raises `Spark.Error.DslError` when two domains claim the same
# client-facing `rpc_action` or `typed_query` name — this only adds the
# guard tests. Each row gets its own domain pair, so compiling one pair's
# manifest (which raises) never blocks testing the other. Kept out of
# `config :ash_kotlin_multiplatform, ash_domains:` — nothing here compiles
# into a Kotlin file, only into a manifest a test builds through the
# `:domains` option.
defmodule AshKotlinMultiplatform.Test.PutUniqueGuard.RpcActionDomainOne do
  @moduledoc "Row 7: claims `rpc_action :create_thing` over `Todo`."
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Todo
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.Todo do
      rpc_action :create_thing, :create
    end
  end
end

defmodule AshKotlinMultiplatform.Test.PutUniqueGuard.RpcActionDomainTwo do
  @moduledoc "Row 7: claims the same `rpc_action :create_thing`, over `Book`."
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Book
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.Book do
      rpc_action :create_thing, :create
    end
  end
end

defmodule AshKotlinMultiplatform.Test.PutUniqueGuard.TypedQueryDomainOne do
  @moduledoc "Row 10: claims `typed_query :thing_titles` over `Todo`."
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Todo
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.Todo do
      typed_query :thing_titles, :read,
        fields: ["id"],
        kotlin_result_type_name: "ThingTitlesResultOne",
        kotlin_fields_const_name: "THING_TITLES_FIELDS_ONE"
    end
  end
end

defmodule AshKotlinMultiplatform.Test.PutUniqueGuard.TypedQueryDomainTwo do
  @moduledoc "Row 10: claims the same `typed_query :thing_titles`, over `Book`."
  use Ash.Domain, extensions: [AshKotlinMultiplatform.Rpc]

  resources do
    resource AshKotlinMultiplatform.Test.Book
  end

  kotlin_rpc do
    resource AshKotlinMultiplatform.Test.Book do
      typed_query :thing_titles, :read,
        fields: ["id"],
        kotlin_result_type_name: "ThingTitlesResultTwo",
        kotlin_fields_const_name: "THING_TITLES_FIELDS_TWO"
    end
  end
end
