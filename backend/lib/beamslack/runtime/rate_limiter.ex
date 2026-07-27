defmodule BeamSlack.Runtime.RateLimiter do
  @moduledoc """
  A per-user message rate limit, backed by ETS. **This is Lab 07 and it is yours
  to implement.** See `docs/labs/07-ets-ownership.md`.

  Codex has written the documentation, the `@spec`s, and the test suite at
  `test/beamslack/runtime/rate_limiter_test.exs`. Every function here raises.

  ## Why ETS and not a GenServer's state

  A rate limiter is consulted on every single message send. If its state lives in
  a GenServer, every send in the entire system is serialized through one process's
  mailbox, and the thing protecting you from overload becomes the thing that
  causes it.

  An ETS table with `read_concurrency` and `write_concurrency` lets any process
  read and write it directly, with no message passing at all. `:ets.update_counter/4`
  is atomic, so a hundred processes can increment the same counter simultaneously
  and the arithmetic is still correct. That is the entire reason ETS exists: shared
  mutable state with no owning process in the request path.

  ## The catch, which is the lab

  An ETS table is owned by a process, and when that process dies the table is
  *deleted*. Not orphaned, not garbage collected later — deleted, immediately, with
  everything in it. So a rate limiter whose owner crashes forgets every limit at
  exactly the moment when something is going wrong.

  `:ets.give_away/3` transfers ownership, and the `heir` option names a process to
  inherit the table when the owner dies. Whether you want that here is the
  interesting question, and it has a real answer either way.

  ## Design decisions that are yours

  The table's type and access mode, who owns it and who creates it, whether there
  is an heir and what the heir does with `{:"ETS-TRANSFER", table, from, data}`,
  how the time window is represented, how expired entries are cleaned up and by
  whom, and whether `allow?/1` and `record/1` are one operation or two.
  """

  @not_implemented """
  Lab 07 is not implemented yet. Read docs/labs/07-ets-ownership.md, then replace \
  the bodies in lib/beamslack/runtime/rate_limiter.ex.
  """

  @typedoc "Whatever the limit is keyed on. A user id, in practice."
  @type key :: String.t()

  @typedoc """
  `:limit` is how many actions are allowed per `:window_ms`. Both default to the
  application config so the tests can shrink them.
  """
  @type option :: {:limit, pos_integer()} | {:window_ms, pos_integer()}

  @doc """
  Records an action for `key` and says whether it is allowed.

  Returns `{:ok, remaining}` when the action is within the limit, and
  `{:error, :rate_limited, retry_after_ms}` when it is not.

  This is deliberately one operation rather than a separate check and record.
  Splitting them creates a window in which two callers both check, both see room,
  and both proceed. Making it atomic is the point, and `:ets.update_counter/4` is
  how.
  """
  @spec hit(key(), [option()]) ::
          {:ok, remaining :: non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def hit(key, opts \\ [])
  def hit(_key, _opts), do: raise(@not_implemented)

  @doc """
  How many actions `key` has left in the current window, without recording one.

  Must not go through a process. If this function sends a message anywhere, the
  design has failed.
  """
  @spec remaining(key(), [option()]) :: non_neg_integer()
  def remaining(key, opts \\ [])
  def remaining(_key, _opts), do: raise(@not_implemented)

  @doc """
  Forgets everything about `key`.
  """
  @spec reset(key()) :: :ok
  def reset(_key), do: raise(@not_implemented)

  @doc """
  Forgets everything about everyone.
  """
  @spec reset_all() :: :ok
  def reset_all, do: raise(@not_implemented)

  @doc """
  The ETS table's name or reference, so tests and the dashboard can inspect it.
  """
  @spec table() :: :ets.table()
  def table, do: raise(@not_implemented)
end
