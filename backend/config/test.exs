import Config

config :bcrypt_elixir, log_rounds: 4

# Lab 05's typing indicator expiry, short enough to observe in a test without
# sleeping through three seconds.
config :beamslack, typing_timeout: 100

# Lab 07's default limit, small and short so its tests are fast. The tests pass
# their own options too; this is what an implementation should fall back to.
config :beamslack, rate_limit: [limit: 5, window_ms: 200]

# The fault-injection routes and the flood target are exercised by their own
# tests, so test gets them too.
config :beamslack, dev_routes: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :beamslack, BeamSlack.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "beamslack_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :beamslack, BeamSlackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "p5SaWQvev4bif8+0AWVpp023lyuOJrFKsLNW0Ani43M1ewAERvr/c5qJMQDRi3Yx",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
