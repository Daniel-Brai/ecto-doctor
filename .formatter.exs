[
  import_deps: [:ecto, :ecto_sql],
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib}/**/*.{ex,exs}",
    "test/*.exs",
    "test/{ecto_doctor,support}/**/*.{ex,exs}"
  ]
]
