defmodule BeamSlack.Dev.LoadTest do
  @moduledoc """
  Opens N real WebSocket connections against a running BeamSlack server and
  reports what happens. Dev and test only.

  This is a client, not a benchmark. It talks the actual Phoenix socket protocol
  over the actual network to a server in another OS process, so what it measures
  includes the parts a unit test cannot: connection setup cost, the socket
  process per connection, PubSub fan-out to every subscriber, and the point at
  which the server stops keeping up.

  ## The numbers to have opinions about before running it

  Each connected client costs one Bandit connection process plus one
  `Phoenix.Socket` process, plus one channel process per joined channel. So 500
  clients in one channel is roughly 1,500 processes — which is nothing; the BEAM
  starts with a limit of about 262,000 and raising it is a VM flag. Predict the
  memory per client before you look, then look.

  Fan-out is the interesting part. Every message sent in a channel with N
  subscribers is N sends. With 500 clients each sending one message per second,
  the server is doing 250,000 pushes per second, and the sending is done by the
  broadcasting process. That is the number that hurts, not the connection count.

  ## Protocol notes

  Phoenix's v2 socket serializer sends JSON arrays, not objects:

      [join_ref, ref, topic, event, payload]

  A reply comes back as the same shape with event `"phx_reply"`. There is no
  library doing this here on purpose — seeing the wire format once makes the
  channel abstraction much less mysterious.
  """

  alias BeamSlack.Dev.LoadTest.Client

  @type opts :: [
          clients: pos_integer(),
          url: String.t(),
          token: String.t(),
          channel_id: String.t(),
          rate: number(),
          duration: pos_integer()
        ]

  @doc """
  Runs the load test and returns a report.

  Blocks for `:duration` seconds, then closes every connection.
  """
  @spec run(opts()) :: map()
  def run(opts) do
    clients = Keyword.fetch!(opts, :clients)
    duration = Keyword.fetch!(opts, :duration)

    started_at = System.monotonic_time(:millisecond)

    pids =
      for index <- 1..clients do
        # Stagger connections. Opening 500 sockets in the same millisecond
        # measures your ability to open sockets, not the server's steady state.
        Process.sleep(Keyword.get(opts, :ramp_ms, 5))

        case Client.start_link(Keyword.put(opts, :index, index)) do
          {:ok, pid} -> pid
          {:error, _reason} -> nil
        end
      end
      |> Enum.reject(&is_nil/1)

    connected_at = System.monotonic_time(:millisecond)

    Process.sleep(duration * 1_000)

    report =
      pids
      |> Enum.map(&Client.stats/1)
      |> summarize()
      |> Map.merge(%{
        requested: clients,
        connected: length(pids),
        connect_ms: connected_at - started_at,
        ran_ms: System.monotonic_time(:millisecond) - connected_at
      })

    Enum.each(pids, &Client.close/1)

    report
  end

  defp summarize(stats) do
    sent = Enum.sum(Enum.map(stats, & &1.sent))
    received = Enum.sum(Enum.map(stats, & &1.received))
    joined = Enum.count(stats, & &1.joined?)
    latencies = stats |> Enum.flat_map(& &1.latencies) |> Enum.sort()

    %{
      joined: joined,
      sent: sent,
      received: received,
      errors: Enum.sum(Enum.map(stats, & &1.errors)),
      latency_p50: percentile(latencies, 0.50),
      latency_p95: percentile(latencies, 0.95),
      latency_p99: percentile(latencies, 0.99),
      latency_max: List.last(latencies)
    }
  end

  defp percentile([], _p), do: nil

  defp percentile(sorted, p) do
    index = sorted |> length() |> Kernel.*(p) |> Float.ceil() |> trunc() |> max(1)
    Enum.at(sorted, index - 1)
  end
end
