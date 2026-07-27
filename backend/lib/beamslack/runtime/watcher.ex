defmodule BeamSlack.Runtime.Watcher do
  @moduledoc """
  Observes other processes and reports their deaths. **This is Lab 06 and it is
  yours to implement.** See `docs/labs/06-monitors-and-links.md`.

  Codex has written the documentation, the `@spec`s, and the test suite at
  `test/beamslack/runtime/watcher_test.exs`. Every function here raises.

  ## Why this exists

  By the end of Track 2, several things in this system need to know when a process
  they did not start has died. A channel runtime needs to drop a user whose socket
  vanished. A cache needs to invalidate an entry whose owner is gone. Nothing in
  the supervision tree helps with any of that, because supervision is about
  processes you *started*, and this is about processes you merely *care about*.

  That is the distinction this lab is built on. A supervisor restarts its children.
  A watcher does not restart anything; it finds out, and tells someone.

  ## The rule this module must not break

  A watcher whose watched process crashes must survive. If watching something can
  kill you, you have built a link, and a link is a bidirectional statement that two
  processes share a fate. That is a real and useful thing — it is how supervision
  works underneath — but it is not what this is.

  The test suite kills watched processes in every way it can think of, including
  `:kill`, and asserts this module is still alive afterwards.

  ## Design decisions that are yours

  Whether this is one process or one per watched target, whether it traps exits and
  why, what happens when the same process is watched twice, whether `watch/2` on an
  already-dead process is an error or an immediate notification, and how a
  subscriber is told. The brief lays out the options.
  """

  @not_implemented """
  Lab 06 is not implemented yet. Read docs/labs/06-monitors-and-links.md, then \
  replace the bodies in lib/beamslack/runtime/watcher.ex.
  """

  @typedoc "Anything you want attached to a watch, returned when it dies."
  @type meta :: term()

  @typedoc """
  What a subscriber receives when a watched process dies. The reason is whatever
  the process exited with: `:normal`, `:killed`, `:shutdown`, or an exception's
  exit term.
  """
  @type down_notification :: {:process_down, pid(), meta(), reason :: term()}

  @doc """
  Starts watching `pid`, attaching `meta` to it.

  Returns `:ok`. Watching a process that is already dead must still result in the
  subscriber being notified — deciding whether that happens synchronously or as a
  message is part of the lab, but silence is not an option, because a caller that
  gets silence cannot tell "it is alive" from "it died a microsecond ago".
  """
  @spec watch(pid(), meta()) :: :ok
  def watch(pid, meta \\ nil)
  def watch(_pid, _meta), do: raise(@not_implemented)

  @doc """
  Stops watching `pid`, and guarantees no notification arrives afterwards.

  The guarantee is the hard part, and `Process.demonitor/2` has an option for
  exactly it. Returns `:ok` even when `pid` was not being watched.
  """
  @spec unwatch(pid()) :: :ok
  def unwatch(_pid), do: raise(@not_implemented)

  @doc """
  Lists the processes currently being watched, with their metadata.
  """
  @spec watched() :: [{pid(), meta()}]
  def watched, do: raise(@not_implemented)

  @doc """
  Registers `subscriber` to receive `t:down_notification/0` messages.

  A subscriber is itself a process that can die. Deciding what the watcher does
  about that is a question the brief asks, and it is recursive in a way worth
  noticing.
  """
  @spec subscribe(pid()) :: :ok
  def subscribe(subscriber \\ self())
  def subscribe(_subscriber), do: raise(@not_implemented)
end
