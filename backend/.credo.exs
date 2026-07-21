%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/", "mix.exs", "*.exs"]
      },
      checks: [
        {Credo.Check.Refactor.MapInto, false},
        {Credo.Check.Refactor.MapInto, false}
      ]
    }
  ]
}
