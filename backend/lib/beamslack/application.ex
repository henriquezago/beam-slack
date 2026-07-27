defmodule BeamSlack.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    BeamSlack.Telemetry.attach_loggers()

    children =
      [
        # Telemetry first: it only samples, so nothing depends on it, but starting
        # it first means it is watching while everything else comes up.
        BeamSlackWeb.Telemetry,
        BeamSlack.Repo,
        # PubSub must start before anything that broadcasts through it, which
        # includes Presence and the Endpoint.
        {Phoenix.PubSub, name: BeamSlack.PubSub},
        BeamSlackWeb.Presence
      ] ++
        dev_children() ++
        [
          # Start to serve requests, typically the last entry
          BeamSlackWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BeamSlack.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeamSlackWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # The flood target is a process that exists to be broken. It has no business
  # being in a production tree, and putting it behind the same flag as the dev
  # routes keeps "can I break this?" a single decision.
  defp dev_children do
    if Application.get_env(:beamslack, :dev_routes, false) do
      [BeamSlack.Dev.FloodTarget]
    else
      []
    end
  end
end
