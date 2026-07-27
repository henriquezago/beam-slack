defmodule BeamSlack.Dev.FloodTarget do
  @moduledoc """
  A process that is deliberately too slow, so you can watch a mailbox win. Dev and
  test only.

  Every BEAM process has an unbounded mailbox. There is no built-in limit, no
  rejection, and no signal to the sender that a process is behind — `send/2`
  always succeeds and always returns immediately, whether the receiver is idle or
  has four million messages queued. That is a deliberate design choice with a
  sharp edge: a producer that is faster than a consumer will consume all available
  memory, and the first symptom is usually not the flooded process failing. It is
  the whole VM slowing down as garbage collection walks an enormous heap that is
  almost entirely one process's mailbox.

  This process handles `{:work, n}` and sleeps `:cost_ms` milliseconds doing it, so
  it drains at a known, terrible rate. Flood it with
  `BeamSlack.Dev.FaultInjection.flood/2` or `mix beamslack.flood`.

  ## What to watch

      iex> BeamSlack.Dev.FloodTarget.stats()
      %{processed: 12, mailbox_len: 9_988, memory_kb: 812, ...}

  `mailbox_len` and `memory_kb` are read from the outside with `Process.info/2`,
  which is why `stats/0` can answer while the process is too busy to. Note that
  `stats/0` is a `call`: it goes to the back of the same queue, so during a flood
  it will time out. That failure is the lesson, not a bug — a `GenServer.call` to
  an overloaded process is itself a way to spread the overload to the caller. Use
  `observe/0`, which never talks to the process at all.

  ## What this module is not

  It is not an example to copy. Lab 08 asks you to build the version that does not
  fall over; this one exists to be the thing it is compared against.
  """

  use GenServer

  @default_cost_ms 5

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Asks the process how it is doing, by sending it a message.

  Times out during a flood, on purpose. See the moduledoc.
  """
  @spec stats(timeout()) :: map() | {:error, :timeout}
  def stats(timeout \\ 1_000) do
    GenServer.call(__MODULE__, :stats, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
  end

  @doc """
  Reads the process's vital signs from the outside, without sending it anything.

  Always answers, however overloaded the target is, because `Process.info/2` is
  handled by the runtime rather than by the process.
  """
  @spec observe() :: map() | {:error, :not_running}
  def observe do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_running}

      pid ->
        info = Process.info(pid, [:message_queue_len, :memory, :reductions, :status])

        %{
          pid: pid,
          mailbox_len: info[:message_queue_len],
          memory_kb: div(info[:memory], 1024),
          reductions: info[:reductions],
          status: info[:status]
        }
    end
  end

  @doc """
  Discards everything queued, so the next experiment starts from zero.

  Implemented as a `selective receive` loop inside the process, which is worth
  reading: draining a mailbox is not an operation the runtime offers, only
  something a process can do to itself.
  """
  @spec drain() :: :ok
  def drain do
    send(__MODULE__, :drain)
    :ok
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       cost_ms: Keyword.get(opts, :cost_ms, @default_cost_ms),
       processed: 0,
       dropped: 0,
       started_at: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, Map.merge(state, external_info()), state}
  end

  @impl true
  def handle_info({:work, _n}, state) do
    Process.sleep(state.cost_ms)
    {:noreply, %{state | processed: state.processed + 1}}
  end

  def handle_info(:drain, state) do
    dropped = drain_mailbox(0)
    {:noreply, %{state | dropped: state.dropped + dropped}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp drain_mailbox(count) do
    receive do
      _anything -> drain_mailbox(count + 1)
    after
      0 -> count
    end
  end

  defp external_info do
    case Process.info(self(), [:message_queue_len, :memory]) do
      nil -> %{}
      info -> %{mailbox_len: info[:message_queue_len], memory_kb: div(info[:memory], 1024)}
    end
  end
end
