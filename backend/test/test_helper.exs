# Lab suites are the specification for work the learner has not written yet, so
# they are excluded from the default run and `mix test` stays green for everything
# else. Run them explicitly:
#
#     mix test.labs                 # only the labs
#     mix test --include lab        # everything, labs included
#
ExUnit.start(exclude: [:lab])
Ecto.Adapters.SQL.Sandbox.mode(BeamSlack.Repo, :manual)
