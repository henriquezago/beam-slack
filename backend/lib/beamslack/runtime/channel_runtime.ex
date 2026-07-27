defmodule BeamSlack.Runtime.ChannelRuntime do
  @moduledoc """
  Ephemeral runtime state for one channel. **This is Lab 01 and it is yours to
  implement.** See `docs/labs/01-channel-runtime.md`.

  Codex has written the public API's documentation, its `@spec`s, and the test
  suite at `test/beamslack/runtime/channel_runtime_test.exs`. Every function here
  currently raises. Replace the bodies, and the internals, with your own design.

  ## What this module is for

  Callers know a `channel_id` and nothing else. They must never hold a PID, never
  know whether a process already exists, and never coordinate startup between
  themselves. That means this module owns three separate concerns:

    * discovery, via a `Registry` named `BeamSlack.Runtime.ChannelRegistry`
    * creation, via a `DynamicSupervisor` named `BeamSlack.Runtime.ChannelSupervisor`
    * lifecycle, meaning when a runtime starts, and who decides that it stops

  Both of those named processes also need to exist in the supervision tree. They
  do not yet.

  ## What this module is not for

  Message history is durable state and belongs in PostgreSQL, reachable through
  `BeamSlack.Messaging`. Nothing that must survive a crash goes in here. If you
  cannot name state that is meaningless after a crash, this process should not
  exist.

  This module does not touch the database at all, which is why its test suite is
  `async: true` and needs no sandbox.

  ## Design decisions that are yours

  How the process is registered and looked up, what prevents two concurrent
  callers from starting two runtimes for the same channel, when a runtime should
  start, how and by whom it is shut down when idle, which restart strategy its
  child spec uses, and where it all sits in the supervision tree. The brief walks
  through each one with the options and their tradeoffs.

  You will also need the GenServer callbacks, which are deliberately absent here:
  deciding which operations are a `call` and which are a `cast` is part of the
  exercise.
  """

  @not_implemented """
  Lab 01 is not implemented yet. Read docs/labs/01-channel-runtime.md, then \
  replace the bodies in lib/beamslack/runtime/channel_runtime.ex.
  """

  @typedoc "The durable channel id this runtime is attached to."
  @type channel_id :: String.t()

  @typedoc "A connected user's id."
  @type user_id :: String.t()

  @typedoc """
  `:idle_timeout` is how long a runtime with nobody connected should wait before
  shutting itself down, in milliseconds. It exists as an option so the tests can
  observe shutdown without sleeping; pick your own default for `get_or_start/1`.
  """
  @type option :: {:idle_timeout, timeout()}

  @doc """
  Returns the runtime for `channel_id`, starting it if it is not already running.

  Must be safe to call concurrently: two simultaneous callers for the same
  channel must both receive the same PID, and only one process may exist.
  """
  @spec get_or_start(channel_id, [option]) :: {:ok, pid} | {:error, term}
  def get_or_start(channel_id, opts \\ [])
  def get_or_start(_channel_id, _opts), do: raise(@not_implemented)

  @doc """
  Returns the PID of the runtime for `channel_id`, or nil if it is not running.

  Read-only: this must never start a process.
  """
  @spec whereis(channel_id) :: pid | nil
  def whereis(_channel_id), do: raise(@not_implemented)

  @doc """
  Records that `user_id` is connected to `channel_id`, starting the runtime if
  needed. This is the ergonomic entry point, and the caller never sees a PID.

  Connected users are deduplicated by id: a user with two tabs open counts once
  here. Multi-device presence is Track 2's problem, not this module's.
  """
  @spec join(channel_id, user_id) :: :ok
  def join(_channel_id, _user_id), do: raise(@not_implemented)

  @doc """
  Records that `user_id` disconnected from `channel_id`.

  Returns `{:error, :not_running}` when no runtime exists. Do not start one just
  to remove somebody from it.
  """
  @spec leave(channel_id, user_id) :: :ok | {:error, :not_running}
  def leave(_channel_id, _user_id), do: raise(@not_implemented)

  @doc """
  Lists the users currently connected to `channel_id`, in no particular order.

  Read-only: returns `[]` for a channel with no runtime rather than starting one.
  """
  @spec connected_users(channel_id) :: [user_id]
  def connected_users(_channel_id), do: raise(@not_implemented)

  @doc """
  Stops the runtime for `channel_id`, and makes sure it stays stopped.

  Idempotent: returns `:ok` even when nothing was running.
  """
  @spec stop(channel_id) :: :ok
  def stop(_channel_id), do: raise(@not_implemented)
end
