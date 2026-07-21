defmodule BeamSlack.Repo do
  use Ecto.Repo,
    otp_app: :beamslack,
    adapter: Ecto.Adapters.Postgres
end
