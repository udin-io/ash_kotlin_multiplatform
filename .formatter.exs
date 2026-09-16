spark_locals_without_parens = [
  argument_names: 1,
  enable_filter?: 1,
  enable_sort?: 1,
  field_names: 1,
  fields: 1,
  get?: 1,
  get_by: 1,
  identities: 1,
  kotlin_fields_const_name: 1,
  kotlin_result_type_name: 1,
  metadata_field_names: 1,
  not_found_error?: 1,
  read_action: 1,
  resource: 1,
  resource: 2,
  rpc_action: 2,
  rpc_action: 3,
  show_metadata: 1,
  type_name: 1,
  typed_query: 2,
  typed_query: 3
]

# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:ash, :ash_phoenix, :spark],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
