# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :beamslack,
  namespace: BeamSlack,
  ecto_repos: [BeamSlack.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  # How long a "user is typing" state survives without another keystroke.
  # Lab 05 reads this so its tests can shorten the window.
  typing_timeout: 3_000,
  # Lab 07's per-user send limit. Read these rather than hardcoding, so the tests
  # can shrink the window.
  rate_limit: [limit: 20, window_ms: 10_000],
  # LiveDashboard and the fault-injection endpoints. Overridden in dev.exs; the
  # routes are compiled out everywhere else.
  dev_routes: false

# Configure the endpoint
config :beamslack, BeamSlackWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: BeamSlackWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BeamSlack.PubSub,
  # Only LiveDashboard uses LiveView here, and only in dev.
  live_view: [signing_salt: "wQ2hkTvR"]

# Configure Elixir's Logger.
#
# The metadata list is what makes these logs structured rather than sentences: a
# key present here is rendered as `key=value` and, more importantly, is available
# as a field to any backend that ships logs somewhere. A key *not* listed here is
# silently dropped, which is the usual reason a Logger.warning/2 call's metadata
# seems to vanish.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :channel_id,
    :sender_id,
    :message_id,
    :user_id,
    :duration_ms,
    :queue_ms,
    :query_ms,
    :total_ms,
    :source,
    :fault_kind,
    :fault_target,
    :fault_detail
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
