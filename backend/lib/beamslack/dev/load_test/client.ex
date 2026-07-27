defmodule BeamSlack.Dev.LoadTest.Client do
  @moduledoc """
  One simulated browser tab: a WebSocket connection that joins a channel, sends
  messages on a timer, and counts what comes back.

  Speaks the Phoenix v2 socket protocol directly. Every frame is a JSON array of
  `[join_ref, ref, topic, event, payload]`, and every push gets a `"phx_reply"`
  carrying the same `ref`, which is how `handle_frame/2` below matches a reply to
  the request that caused it and records a round-trip latency.

  It also has to send `"heartbeat"` on the `"phoenix"` topic, or the server closes
  the connection after 60 seconds. That heartbeat is not a formality: it is what
  lets the server notice a client that vanished without closing, which is the same
  problem presence has in Lab 04.
  """

  use WebSockex

  require Logger

  @heartbeat_ms 30_000
  @join_ref "1"

  @type state :: %{
          topic: String.t(),
          joined?: boolean(),
          ref: non_neg_integer(),
          sent: non_neg_integer(),
          received: non_neg_integer(),
          errors: non_neg_integer(),
          pending: %{String.t() => integer()},
          latencies: [integer()],
          send_interval_ms: pos_integer() | nil,
          index: pos_integer()
        }

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    url = build_url(Keyword.fetch!(opts, :url), Keyword.fetch!(opts, :token))
    rate = Keyword.get(opts, :rate, 0)

    state = %{
      topic: "channel:#{Keyword.fetch!(opts, :channel_id)}",
      joined?: false,
      ref: 1,
      sent: 0,
      received: 0,
      errors: 0,
      pending: %{},
      latencies: [],
      send_interval_ms: if(rate > 0, do: round(1_000 / rate), else: nil),
      index: Keyword.get(opts, :index, 1)
    }

    WebSockex.start_link(url, __MODULE__, state, async: false, handle_initial_conn_failure: true)
  end

  @spec stats(pid()) :: map()
  def stats(pid) do
    # WebSockex has no call/2, so state is fetched with a plain process message
    # answered from handle_info/2.
    send(pid, {:stats, self()})

    receive do
      {:stats, ^pid, stats} -> stats
    after
      2_000 -> %{joined?: false, sent: 0, received: 0, errors: 1, latencies: []}
    end
  end

  @spec close(pid()) :: :ok
  def close(pid) do
    Process.exit(pid, :normal)
    :ok
  end

  @impl true
  def handle_connect(_conn, state) do
    send(self(), :join)
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:join, state) do
    {frame, state} = encode(state, state.topic, "phx_join", %{})
    {:reply, frame, state}
  end

  def handle_info(:heartbeat, state) do
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    {frame, state} = encode(state, "phoenix", "heartbeat", %{})
    {:reply, frame, state}
  end

  def handle_info(:send_message, state) do
    if state.send_interval_ms do
      Process.send_after(self(), :send_message, state.send_interval_ms)
    end

    body = "load test #{state.index} #{state.sent + 1}"
    {frame, state} = encode(state, state.topic, "new_message", %{"body" => body})

    {:reply, frame, %{state | sent: state.sent + 1}}
  end

  def handle_info({:stats, from}, state) do
    send(
      from,
      {:stats, self(), Map.take(state, [:joined?, :sent, :received, :errors, :latencies])}
    )

    {:ok, state}
  end

  def handle_info(_other, state), do: {:ok, state}

  @impl true
  def handle_frame({:text, raw}, state) do
    case Jason.decode(raw) do
      {:ok, [_join_ref, ref, _topic, "phx_reply", payload]} ->
        {:ok, handle_reply(ref, payload, state)}

      {:ok, [_join_ref, _ref, _topic, "new_message", _payload]} ->
        {:ok, %{state | received: state.received + 1}}

      {:ok, _other} ->
        {:ok, state}

      {:error, _reason} ->
        {:ok, %{state | errors: state.errors + 1}}
    end
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl true
  def handle_disconnect(_status, state) do
    # Reconnect, because a load test that quietly shrinks reports numbers for a
    # smaller test than the one you asked for.
    {:reconnect, %{state | joined?: false, errors: state.errors + 1}}
  end

  defp handle_reply(ref, payload, state) do
    {sent_at, pending} = Map.pop(state.pending, ref)

    state = %{state | pending: pending}
    state = record_latency(state, sent_at)

    case payload do
      %{"status" => "ok"} -> maybe_start_sending(state, ref)
      _error -> %{state | errors: state.errors + 1}
    end
  end

  defp record_latency(state, nil), do: state

  defp record_latency(state, sent_at) do
    latency = System.monotonic_time(:millisecond) - sent_at
    %{state | latencies: [latency | state.latencies]}
  end

  # The join is always ref 1, so a successful reply to it starts the send loop.
  defp maybe_start_sending(%{joined?: false} = state, "1") do
    if state.send_interval_ms do
      Process.send_after(self(), :send_message, :rand.uniform(state.send_interval_ms))
    end

    %{state | joined?: true}
  end

  defp maybe_start_sending(state, _ref), do: state

  defp encode(state, topic, event, payload) do
    ref = to_string(state.ref)
    frame = Jason.encode!([@join_ref, ref, topic, event, payload])

    state = %{
      state
      | ref: state.ref + 1,
        pending: Map.put(state.pending, ref, System.monotonic_time(:millisecond))
    }

    {{:text, frame}, state}
  end

  defp build_url(base, token) do
    base
    |> String.replace_prefix("http://", "ws://")
    |> String.replace_prefix("https://", "wss://")
    |> Kernel.<>("/socket/websocket?vsn=2.0.0&token=#{URI.encode_www_form(token)}")
  end
end
