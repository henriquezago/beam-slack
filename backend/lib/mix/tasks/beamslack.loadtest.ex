defmodule Mix.Tasks.Beamslack.Loadtest do
  @shortdoc "Opens N WebSocket clients against a running server and reports latency"

  @moduledoc """
  Opens N real WebSocket connections to a running BeamSlack server, joins them all
  to one channel, and has each send messages at a fixed rate.

      # terminal 1
      mix phx.server

      # terminal 2
      mix beamslack.loadtest --clients 50 --rate 1 --duration 20

  It logs in over the REST API as a seeded user, finds a workspace and channel, and
  uses that token for every client, so all N connections are the same user unless
  you pass `--email`. That is fine for load and wrong for presence: one user with
  50 tabs is *one* presence entry, which is a good thing to see happen.

  ## What to watch while it runs

  Open <http://localhost:4000/dev/dashboard> alongside it. The Processes page
  sorted by message queue, and the Metrics page, are where the interesting things
  appear. Also open a browser tab on the same channel and try to use it.

  Ramp the client count until something degrades, and identify *what* degraded:
  connection setup, message latency, the database, or the whole VM. They fail in
  different orders and the order is the point.

  ## Options

    * `--clients` — connections to open, default 25
    * `--rate` — messages per second per client, default 1. Use 0 for connect-only.
    * `--duration` — seconds to run, default 15
    * `--channel` — a channel id, default the first channel of the first workspace
    * `--url` — server base url, default http://localhost:4000
    * `--email`, `--password` — the seeded account to log in as
    * `--ramp-ms` — delay between opening connections, default 5
  """

  use Mix.Task

  alias BeamSlack.Dev.LoadTest

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    {opts, _args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          clients: :integer,
          rate: :float,
          duration: :integer,
          channel: :string,
          url: :string,
          email: :string,
          password: :string,
          ramp_ms: :integer
        ]
      )

    Application.ensure_all_started(:req)
    Application.ensure_all_started(:websockex)

    url = Keyword.get(opts, :url, "http://localhost:4000")
    clients = Keyword.get(opts, :clients, 25)

    token = log_in(url, opts)
    channel_id = Keyword.get(opts, :channel) || first_channel(url, token)

    Mix.shell().info("""

    #{clients} clients -> #{url}
    channel #{channel_id}, #{Keyword.get(opts, :rate, 1.0)} msg/s each, \
    #{Keyword.get(opts, :duration, 15)}s

    Watch #{url}/dev/dashboard while this runs.
    """)

    report =
      LoadTest.run(
        clients: clients,
        url: url,
        token: token,
        channel_id: channel_id,
        rate: Keyword.get(opts, :rate, 1.0),
        duration: Keyword.get(opts, :duration, 15),
        ramp_ms: Keyword.get(opts, :ramp_ms, 5)
      )

    print(report)
  end

  defp print(report) do
    Mix.shell().info("""

    connected     #{report.connected} of #{report.requested} in #{report.connect_ms}ms
    joined        #{report.joined}
    sent          #{report.sent}
    received      #{report.received}
    errors        #{report.errors}

    latency p50   #{format_ms(report.latency_p50)}
    latency p95   #{format_ms(report.latency_p95)}
    latency p99   #{format_ms(report.latency_p99)}
    latency max   #{format_ms(report.latency_max)}
    """)

    if report.sent > 0 and report.received == 0 do
      Mix.shell().error("""
      Nothing was received. Either Lab 02's handle_in("new_message", ...) is not
      implemented yet, in which case this is expected, or the broadcast is not
      reaching subscribers. Check the server logs.
      """)
    end

    if report.received > 0 do
      fanout = Float.round(report.received / max(report.sent, 1), 1)

      Mix.shell().info("""
      Each sent message was received #{fanout} times across all clients. Compare
      that to the number of clients, and decide whether the difference is the
      sender being excluded, a slow join, or messages being dropped.
      """)
    end
  end

  defp format_ms(nil), do: "-"
  defp format_ms(ms), do: "#{ms}ms"

  defp log_in(url, opts) do
    email = Keyword.get(opts, :email, "alice@example.com")
    password = Keyword.get(opts, :password, "password123")

    case Req.post("#{url}/api/session", json: %{email: email, password: password}) do
      {:ok, %{status: status, body: %{"data" => %{"token" => token}}}}
      when status in [200, 201] ->
        token

      {:ok, %{status: status, body: body}} ->
        Mix.raise("""
        Could not log in as #{email} (HTTP #{status}): #{inspect(body)}

        Run `mix run priv/repo/seeds.exs` to create the sample accounts.
        """)

      {:error, reason} ->
        Mix.raise("Could not reach #{url}: #{inspect(reason)}. Is `mix phx.server` running?")
    end
  end

  defp first_channel(url, token) do
    headers = [{"authorization", "Bearer #{token}"}]

    with {:ok, %{status: 200, body: %{"data" => [workspace | _rest]}}} <-
           Req.get("#{url}/api/workspaces", headers: headers),
         {:ok, %{status: 200, body: %{"data" => [channel | _rest]}}} <-
           Req.get("#{url}/api/workspaces/#{workspace["id"]}/channels", headers: headers) do
      channel["id"]
    else
      _other ->
        Mix.raise("""
        Could not find a workspace with a channel. Run:

            mix run priv/repo/seeds.exs
        """)
    end
  end
end
