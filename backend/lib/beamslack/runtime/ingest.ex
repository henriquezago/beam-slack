defmodule BeamSlack.Runtime.Ingest do
  @moduledoc """
  A work intake that refuses to drown. **This is Lab 08 and it is yours to
  implement.** See `docs/labs/08-backpressure.md`.

  Codex has written the documentation, the `@spec`s, and the test suite at
  `test/beamslack/runtime/ingest_test.exs`. Every function here raises.

  ## The thing to fix

  `BeamSlack.Dev.FloodTarget` is the same idea done wrong on purpose: a process
  that accepts everything sent to it and falls further behind forever. Run
  `mix beamslack.flood --watch` and look at it before starting. Nothing about that
  process is broken in a way a crash would reveal. It just quietly accumulates,
  and the first visible symptom is the VM slowing down.

  This module does the same job and stays honest about its capacity.

  ## The rule

  `send/2` cannot fail, cannot block, and cannot report a queue length. So a
  process cannot be protected from a flood *by* `send/2`. Backpressure has to come
  from somewhere else, and there are only really three places it can come from:

    * the sender waits for a reply, so its own rate is capped by the receiver's
      (this is what `GenServer.call/3` does, and why a `call` is not just a `cast`
      with a return value)
    * the receiver inspects its own mailbox and refuses or sheds
    * something between them holds a bounded buffer and tells producers to stop

  Each of those pushes the problem somewhere different. Deciding *where the pain
  should land* is the whole design.

  ## Design decisions that are yours

  Whether intake is a `call` or a `cast`, how the bound is enforced and measured,
  whether excess work is rejected, shed, or made to wait, whether the process
  behind the intake is the same process as the intake, and what a caller learns
  when the system is full.
  """

  @not_implemented """
  Lab 08 is not implemented yet. Read docs/labs/08-backpressure.md, then replace \
  the bodies in lib/beamslack/runtime/ingest.ex.
  """

  @typedoc "A unit of work. Opaque to this module."
  @type work :: term()

  @typedoc """
  `:max_queue` is the most work the intake will hold before it starts refusing.
  `:cost_ms` is how long a single unit takes to process, and exists so the tests
  can make the consumer slow enough to fall behind.
  """
  @type option :: {:max_queue, pos_integer()} | {:cost_ms, non_neg_integer()}

  @doc """
  Submits `work`, or refuses it.

  Returns `:ok` when the work was accepted, and `{:error, :overloaded, queue_len}`
  when it was not. It must never block indefinitely, and it must never accept work
  it has no intention of doing — an accepted-then-silently-dropped unit is worse
  than a rejection, because the caller believes it succeeded.
  """
  @spec submit(work(), [option()]) :: :ok | {:error, :overloaded, non_neg_integer()}
  def submit(work, opts \\ [])
  def submit(_work, _opts), do: raise(@not_implemented)

  @doc """
  How much work is waiting.

  Must answer even when the intake is saturated. If this is a `GenServer.call/3`,
  it will time out exactly when you most want to know the answer, which is the
  lesson `BeamSlack.Dev.FloodTarget.stats/0` exists to teach.
  """
  @spec queue_len() :: non_neg_integer()
  def queue_len, do: raise(@not_implemented)

  @doc """
  Counters since the last `reset/0`: accepted, rejected, and completed.

  `accepted` must equal `completed` plus whatever is still queued. If it does not,
  work was accepted and lost.
  """
  @spec stats() :: %{
          accepted: non_neg_integer(),
          rejected: non_neg_integer(),
          completed: non_neg_integer()
        }
  def stats, do: raise(@not_implemented)

  @doc """
  Zeroes the counters and discards queued work.
  """
  @spec reset() :: :ok
  def reset, do: raise(@not_implemented)
end
