defmodule BeamSlack.Telemetry do
  @moduledoc """
  BeamSlack's own telemetry events, and the structured log handler that renders
  them.

  Every event here is emitted with `:telemetry.execute/3`, which runs each attached
  handler **synchronously, in the calling process**. That has two consequences
  worth keeping in mind for the rest of Track 3:

    * a slow handler is added directly to the latency of whatever emitted the
      event, so a handler must not do I/O or call another process
    * a handler that raises is detached by `:telemetry` after the failure, so a
      buggy handler silently stops reporting rather than crashing the caller.
      If metrics stop appearing, suspect this first and check the logs for
      `:telemetry` handler failures.

  ## Events

    * `[:beamslack, :message, :sent]` — measurements `%{duration: native}`,
      metadata `%{channel_id: id, sender_id: id, message_id: id}`
    * `[:beamslack, :fault, :injected]` — measurements `%{count: 1}`, metadata
      `%{kind: atom, target: String.t(), detail: term()}`
    * `[:beamslack, :channel]` — measurements `%{mailbox_len: integer}`, metadata
      `%{name: String.t()}`, sampled by the poller
    * `[:beamslack, :runtime]` — measurements `%{channel_count: integer}`, sampled

  `BeamSlackWeb.Telemetry.metrics/0` aggregates these for the dashboard.
  """

  require Logger

  @doc """
  Times `fun` and emits `[:beamslack, :message, :sent]` with the result's metadata.

  Only emits on success, because a failed insert is not a sent message. Whether
  the failure deserves its own event is a reasonable question and an easy thing to
  add once you have decided what you would do with it.
  """
  @spec span_message_send((-> {:ok, struct()} | {:error, term()})) ::
          {:ok, struct()} | {:error, term()}
  def span_message_send(fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start

    case result do
      {:ok, message} ->
        :telemetry.execute(
          [:beamslack, :message, :sent],
          %{duration: duration, count: 1},
          %{
            channel_id: message.channel_id,
            sender_id: message.sender_id,
            message_id: message.id
          }
        )

      _error ->
        :ok
    end

    result
  end

  @doc """
  Announces an injected fault, so the dashboard and the logs agree on what was
  broken and when.
  """
  @spec fault_injected(atom(), String.t(), keyword()) :: :ok
  def fault_injected(kind, target, detail \\ []) do
    :telemetry.execute(
      [:beamslack, :fault, :injected],
      %{count: 1},
      %{kind: kind, target: target, detail: detail}
    )
  end

  @doc """
  Attaches the structured log handlers.

  Called from `BeamSlack.Application.start/2`. Idempotent: re-attaching the same
  handler id returns `{:error, :already_exists}`, which is fine on a code reload.
  """
  @spec attach_loggers() :: :ok
  def attach_loggers do
    handlers = [
      {"beamslack-message-sent", [:beamslack, :message, :sent], &__MODULE__.log_message_sent/4},
      {"beamslack-fault-injected", [:beamslack, :fault, :injected],
       &__MODULE__.log_fault_injected/4},
      {"beamslack-slow-query", [:beamslack, :repo, :query], &__MODULE__.log_slow_query/4}
    ]

    for {id, event, handler} <- handlers do
      :telemetry.attach(id, event, handler, %{})
    end

    :ok
  end

  @doc false
  def log_message_sent(_event, %{duration: duration}, metadata, _config) do
    Logger.debug("message sent",
      channel_id: metadata.channel_id,
      sender_id: metadata.sender_id,
      message_id: metadata.message_id,
      duration_ms: native_to_ms(duration)
    )
  end

  @doc false
  def log_fault_injected(_event, _measurements, metadata, _config) do
    Logger.warning("fault injected",
      fault_kind: metadata.kind,
      fault_target: metadata.target,
      fault_detail: inspect(metadata.detail)
    )
  end

  @doc false
  def log_slow_query(_event, measurements, metadata, _config) do
    total = Map.get(measurements, :total_time, 0)
    queue = Map.get(measurements, :queue_time, 0)

    cond do
      native_to_ms(queue) > 50 ->
        # Time spent waiting for a connection, not executing. This is the signal
        # that the pool is the bottleneck, and it is the first thing to appear
        # when the fault injector drops Repo connections.
        Logger.warning("db pool saturated",
          queue_ms: native_to_ms(queue),
          query_ms: native_to_ms(Map.get(measurements, :query_time, 0)),
          source: metadata[:source]
        )

      native_to_ms(total) > 200 ->
        Logger.warning("slow query",
          total_ms: native_to_ms(total),
          source: metadata[:source]
        )

      true ->
        :ok
    end
  end

  defp native_to_ms(native) do
    native |> System.convert_time_unit(:native, :microsecond) |> Kernel./(1_000)
  end
end
