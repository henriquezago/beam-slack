defmodule BeamSlack.Dev.FaultInjection do
  @moduledoc """
  Deliberate, controlled breakage. Dev and test only.

  Reading about supervision trees teaches you what OTP claims. Killing a process
  and watching what happens to a browser tab teaches you what OTP does. This module
  exists so you can do the second thing repeatedly, from a mix task, an HTTP call,
  or an IEx session, without hand-typing pids.

  Every function refuses to run in `:prod`. That guard is `enabled?/0`, and the
  reason it is a runtime check on `Mix.env()` rather than a compile-time `if` is so
  that a mistake shows up as an obvious error rather than an undefined function.

  ## The kill reason matters

  `Process.exit(pid, :kill)` is untrappable and immediate. `Process.exit(pid,
  :shutdown)` and any other reason can be trapped, so a process that sets
  `Process.flag(:trap_exit, true)` receives it as a message and can refuse to die.
  The difference is not a detail: it changes whether `terminate/2` runs, whether
  cleanup happens, and whether a supervisor's `:shutdown` timeout is respected.
  Kill the same process with both and note what differs.

  ## Suggested experiments

      # Watch a browser tab. Which of these does the user notice?
      mix beamslack.kill presence
      mix beamslack.kill pubsub
      mix beamslack.kill repo
      mix beamslack.kill endpoint

  For each one, before you run it, write down: does the process restart, what
  restarts it, what state is lost, and what does the client have to do. Lab 09 is
  where those answers get collected into a matrix.
  """

  alias BeamSlack.Telemetry

  @targets %{
    "repo" => BeamSlack.Repo,
    "pubsub" => BeamSlack.PubSub,
    "presence" => BeamSlackWeb.Presence,
    "endpoint" => BeamSlackWeb.Endpoint,
    "telemetry" => BeamSlackWeb.Telemetry,
    "poller" => BeamSlack.Poller,
    "flood_target" => BeamSlack.Dev.FloodTarget,
    # Lab processes. Absent until the learner adds them to the tree, which is
    # itself informative: `mix beamslack.kill channel_supervisor` failing with
    # :not_running is how you find out you never started it.
    "channel_supervisor" => BeamSlack.Runtime.ChannelSupervisor,
    "channel_registry" => BeamSlack.Runtime.ChannelRegistry,
    "watcher" => BeamSlack.Runtime.Watcher,
    "rate_limiter" => BeamSlack.Runtime.RateLimiter,
    "ingest" => BeamSlack.Runtime.Ingest
  }

  @type target :: String.t()
  @type kill_reason :: :kill | :shutdown | atom()

  @doc """
  Whether fault injection is permitted in the current environment.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    function_exported?(Mix, :env, 0) and Mix.env() in [:dev, :test]
  end

  @doc """
  The names that `kill/2` understands, and whether each is currently alive.
  """
  @spec targets() :: [%{name: target(), module: module(), pid: pid() | nil}]
  def targets do
    @targets
    |> Enum.map(fn {name, module} ->
      %{name: name, module: module, pid: Process.whereis(module)}
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Kills a named process.

  Returns `{:ok, %{pid: pid, restarted_as: pid | nil, tree_alive?: boolean}}`.
  `restarted_as` is read after a short settle, so it tells you whether a
  supervisor put something back and whether the replacement is a different
  process — which it always is. A "restarted" process is a new process with the
  same name, not a resumed one, and every pid anybody was holding is now stale.
  That is the whole reason names and registries exist.

  `tree_alive?` exists because a single kill can take down the entire
  application, and `mix beamslack.kill presence` does. Try it and read the log.
  The chain is worth following in full: the name `BeamSlackWeb.Presence` is
  registered to a supervisor *inside* the Presence subtree, not to the child of
  `BeamSlack.Supervisor`, so killing it makes the tracker supervisor restart its
  shard — while the previous shard is still shutting down and still holds the
  name. The restart fails with `already started`, which counts as a restart,
  three times in a row inside the default `max_restarts` window, and the failure
  propagates all the way up.

  Nothing there is a bug in Phoenix. It is what "restart" means when a restart is
  faster than the previous instance's shutdown, and it is the reason
  `max_restarts` exists at all.
  """
  @spec kill(target(), kill_reason()) ::
          {:ok, %{pid: pid(), restarted_as: pid() | nil, tree_alive?: boolean()}}
          | {:error, :disabled | :unknown_target | :not_running}
  def kill(target, reason \\ :kill)

  def kill(target, reason) do
    with :ok <- check_enabled(),
         {:ok, module} <- fetch_target(target),
         pid when is_pid(pid) <- Process.whereis(module) do
      Telemetry.fault_injected(:kill, target, reason: reason, pid: inspect(pid))

      ref = Process.monitor(pid)
      Process.exit(pid, reason)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1_000 ->
          # It trapped the exit and declined. That is a result, not a failure.
          Process.demonitor(ref, [:flush])
      end

      Process.sleep(settle_time())

      {:ok,
       %{
         pid: pid,
         restarted_as: Process.whereis(module),
         tree_alive?: is_pid(Process.whereis(BeamSlack.Supervisor))
       }}
    else
      nil -> {:error, :not_running}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Kills every connection process in the `Repo`'s pool.

  This is not the same as stopping the `Repo`. The pool supervisor survives, and
  DBConnection reconnects on its own schedule with backoff, so what you are
  watching is a *lower* layer's recovery than a supervisor restart. Queries issued
  during the gap do not crash the caller by default; they queue, and then fail with
  a `DBConnection.ConnectionError` once the queue target is exceeded.

  Compare the user-visible result of this with `kill("repo")`.
  """
  @spec drop_db_connections() :: {:ok, %{killed: non_neg_integer()}} | {:error, :disabled}
  def drop_db_connections do
    with :ok <- check_enabled() do
      pids = repo_connection_pids()

      Telemetry.fault_injected(:drop_db_connections, "repo", count: length(pids))

      Enum.each(pids, &Process.exit(&1, :kill))

      {:ok, %{killed: length(pids)}}
    end
  end

  @doc """
  Sends `count` messages to a process faster than it can possibly drain them.

  The target defaults to `BeamSlack.Dev.FloodTarget`, which sleeps on every
  message on purpose. Pointing this at a real process is allowed and instructive;
  pointing it at `BeamSlack.Repo` is how you learn that a `GenServer` with an
  unbounded mailbox has no way to say "stop".

  Returns immediately. Watch the mailbox grow on the dashboard's Metrics page or
  with `mix beamslack.flood --watch`.
  """
  @spec flood(pos_integer(), keyword()) :: {:ok, %{sent: pos_integer()}} | {:error, term()}
  def flood(count, opts \\ []) do
    target = Keyword.get(opts, :target, BeamSlack.Dev.FloodTarget)
    message = Keyword.get(opts, :message, :work)

    with :ok <- check_enabled(),
         pid when is_pid(pid) <- Process.whereis(target) do
      Telemetry.fault_injected(:flood, inspect(target), count: count)

      # From a separate process, so the caller is not itself blocked, and so the
      # sender's own scheduling does not become the limiting factor.
      spawn(fn -> send_many(pid, message, count) end)

      {:ok, %{sent: count}}
    else
      nil -> {:error, :not_running}
      other -> other
    end
  end

  @doc """
  A snapshot of the processes worth watching while something is broken.
  """
  @spec snapshot() :: %{atom() => term()}
  def snapshot do
    %{
      process_count: :erlang.system_info(:process_count),
      run_queue: :erlang.statistics(:total_run_queue_lengths),
      memory_kb: div(:erlang.memory(:total), 1024),
      targets:
        Enum.map(targets(), fn target ->
          Map.put(target, :mailbox_len, mailbox_len(target.pid))
        end)
    }
  end

  defp send_many(pid, message, count) do
    Enum.each(1..count, fn n -> send(pid, {message, n}) end)
  end

  defp mailbox_len(nil), do: nil

  defp mailbox_len(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      nil -> nil
    end
  end

  defp check_enabled do
    if enabled?(), do: :ok, else: {:error, :disabled}
  end

  defp fetch_target(name) do
    case Map.fetch(@targets, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_target}
    end
  end

  @doc """
  The pool's connection processes.

  Found by scanning every process on the node for a `$initial_call` of
  `DBConnection.Connection`, rather than by walking the `Repo`'s supervision tree,
  because they are not in it: `DBConnection` starts connections under a watcher in
  its own application, and the `Repo` supervisor only owns the pool. Which is
  itself the answer to "why did killing the Repo not close my connections".
  """
  @spec repo_connection_pids() :: [pid()]
  def repo_connection_pids do
    Enum.filter(Process.list(), &connection_process?/1)
  end

  defp connection_process?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} -> connection_initial_call?(dict[:"$initial_call"])
      nil -> false
    end
  end

  defp connection_initial_call?({DBConnection.Connection, _fun, _arity}), do: true
  defp connection_initial_call?({Postgrex.Protocol, _fun, _arity}), do: true
  defp connection_initial_call?(_other), do: false

  # Long enough for a one_for_one restart to have happened, short enough that a
  # mix task still feels immediate.
  defp settle_time, do: 200
end
