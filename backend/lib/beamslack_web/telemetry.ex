defmodule BeamSlackWeb.Telemetry do
  @moduledoc """
  Telemetry metric definitions and the poller that samples the VM.

  Telemetry has two halves that are easy to conflate. `:telemetry` itself is a
  synchronous pub/sub for measurement events: `Plug.Telemetry`, Ecto, and Phoenix
  all `:telemetry.execute/3` at interesting moments, and every attached handler
  runs *in the process that emitted the event*. `Telemetry.Metrics`, defined in
  `metrics/0` below, is only a description of how to aggregate those events; it
  does no work until a reporter subscribes to it. `Phoenix.LiveDashboard` is the
  reporter here, which is why the metrics show up on the dashboard's Metrics page
  and nowhere else.

  `:telemetry_poller` covers what no event can tell you, because nothing emits an
  event when memory grows: it periodically samples VM counters and emits them as
  events so the same pipeline can carry them.

  Things worth noticing while breaking the system in Track 3:

    * `vm.total_run_queue_lengths` is the clearest signal that schedulers are
      backed up, and it stays low even when one process is drowning, because one
      overloaded process is not a busy scheduler.
    * `beamslack.channel.mailbox_len` is sampled by `measure_channel_mailboxes/0`
      and is what makes the mailbox flood in `mix beamslack.flood` visible.
  """

  use Supervisor

  import Telemetry.Metrics

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller,
       measurements: periodic_measurements(), period: 5_000, name: BeamSlack.Poller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  The metric definitions the LiveDashboard reporter renders.
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      # Phoenix
      summary("phoenix.endpoint.start.system_time", unit: {:native, :millisecond}),
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      counter("phoenix.error_rendered.count", tags: [:status]),
      summary("phoenix.socket_connected.duration", unit: {:native, :millisecond}),
      counter("phoenix.channel_joined.count", tags: [:result]),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database. `queue_time` climbing while `query_time` stays flat means the
      # pool is exhausted, not that PostgreSQL is slow. Those need different fixes.
      summary("beamslack.repo.query.total_time", unit: {:native, :millisecond}),
      summary("beamslack.repo.query.decode_time", unit: {:native, :millisecond}),
      summary("beamslack.repo.query.query_time", unit: {:native, :millisecond}),
      summary("beamslack.repo.query.queue_time", unit: {:native, :millisecond}),
      summary("beamslack.repo.query.idle_time", unit: {:native, :millisecond}),

      # BeamSlack's own events, emitted by BeamSlack.Telemetry.
      counter("beamslack.message.sent.count", tags: [:channel_id]),
      summary("beamslack.message.sent.duration", unit: {:native, :millisecond}),
      counter("beamslack.fault.injected.count", tags: [:kind, :target]),
      last_value("beamslack.channel.mailbox_len", tags: [:name]),
      last_value("beamslack.runtime.channel_count"),

      # VM
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.memory.processes", unit: {:byte, :kilobyte}),
      last_value("vm.memory.ets", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),
      last_value("vm.system_counts.process_count")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_channel_mailboxes, []},
      {__MODULE__, :measure_runtime_channels, []}
    ]
  end

  @doc """
  Samples the mailbox length of every process that registered itself as
  interesting, which currently means the flood harness targets.

  A process's mailbox length is observable from the outside with
  `Process.info(pid, :message_queue_len)` without asking the process anything —
  which is the only reason this works when the process is too busy to reply.
  """
  @spec measure_channel_mailboxes() :: :ok
  def measure_channel_mailboxes do
    for {name, pid} <- monitored_processes(), is_pid(pid) do
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} ->
          :telemetry.execute([:beamslack, :channel], %{mailbox_len: len}, %{name: name})

        nil ->
          :ok
      end
    end

    :ok
  end

  @doc """
  Reports how many channel runtime processes are alive.

  Returns zero until Lab 01 is implemented, since there is no supervisor to count
  children of yet.
  """
  @spec measure_runtime_channels() :: :ok
  def measure_runtime_channels do
    count =
      case Process.whereis(BeamSlack.Runtime.ChannelSupervisor) do
        nil -> 0
        pid -> DynamicSupervisor.count_children(pid).active
      end

    :telemetry.execute([:beamslack, :runtime], %{channel_count: count}, %{})
  catch
    # count_children/1 calls into the supervisor, which may be mid-restart or may
    # not be a DynamicSupervisor at all while Lab 01 is in progress. A metric is
    # never worth crashing the poller for.
    _kind, _reason -> :ok
  end

  defp monitored_processes do
    [
      {"flood_target", Process.whereis(BeamSlack.Dev.FloodTarget)},
      {"presence", Process.whereis(BeamSlackWeb.Presence)},
      {"pubsub", Process.whereis(BeamSlack.PubSub)}
    ]
  end
end
