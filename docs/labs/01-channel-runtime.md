# Lab 01 — Channel Runtime Discovery and Lifecycle

Track 1. Concepts: `Registry`, `:via` tuples, `DynamicSupervisor`, process
lifecycle, start races, restart strategies, supervision-tree ordering.

## The problem

You have a GenServer that holds ephemeral per-channel runtime state. Right now the
only way to talk to it is to hold its PID, which means every caller has to know
when it was started and has to notice when it dies. That does not survive contact
with a web application: an HTTP request or a WebSocket join arrives knowing only a
`channel_id`, and it has no idea whether a process for that channel exists.

What callers actually want is:

```elixir
ChannelRuntime.join(channel_id, user_id)
```

with no PID anywhere in sight, and no caller needing to know whether that call
just created a process or found one that has been running for an hour.

Getting there means answering three separate questions that are easy to conflate:
how a process is *found* (registration), how it is *created* (dynamic
supervision), and how it is *destroyed* (lifecycle). The interesting part of this
lab is that "find or create" is not an atomic operation, and BeamSlack will call
it concurrently from the very first WebSocket join.

## What already exists

Your Phase 2–5 experiments, in `backend/lib/beamslack/experiments/`:

* `ChannelProcess` — a GenServer holding `%{channel_id, users, active_connections}`,
  with `join/2`, `leave/2`, and `get_state/1` over a PID.
* `ChannelSupervisor` — a static `Supervisor` with one `:transient` child.
* `ChannelDynamicSupervisor` — a `DynamicSupervisor` with `start_channel/1` and
  `stop_channel/1`, also PID-oriented.

Nothing is in the supervision tree. `BeamSlack.Application` still starts only
`[BeamSlack.Repo, BeamSlackWeb.Endpoint]`.

This lab promotes that experimental code into a real, supervised
`BeamSlack.Runtime` namespace. Keep the experiments directory if you want it as a
record of the earlier phases; the new namespace is where the application will
actually look.

Codex has left you a skeleton at
`backend/lib/beamslack/runtime/channel_runtime.ex` containing the module
documentation, the `@spec`s, and function bodies that raise, plus a test suite at
`backend/test/beamslack/runtime/channel_runtime_test.exs`.

Lab suites are tagged `:lab` and excluded from the default run, so `mix test`
stays green for everything else. Run yours with:

```
mix test.labs
```

## The API contract

Codex fixed the public function signatures and two process names so the test
suite could be written. Everything about *how* they work is yours.

```elixir
BeamSlack.Runtime.ChannelRegistry     # the Registry
BeamSlack.Runtime.ChannelSupervisor   # the DynamicSupervisor
```

```elixir
@type channel_id :: String.t()
@type user_id :: String.t()

@spec get_or_start(channel_id) :: {:ok, pid} | {:error, term}
@spec get_or_start(channel_id, keyword) :: {:ok, pid} | {:error, term}
@spec whereis(channel_id) :: pid | nil
@spec join(channel_id, user_id) :: :ok
@spec leave(channel_id, user_id) :: :ok | {:error, :not_running}
@spec connected_users(channel_id) :: [user_id]
@spec stop(channel_id) :: :ok
```

Behavior the tests pin down:

* `join/2` starts the runtime if it is not running. It is the ergonomic entry
  point, and callers never see a PID.
* `whereis/1` and `connected_users/1` are **read-only**: they must not start a
  process. `whereis/1` returns `nil` and `connected_users/1` returns `[]` for a
  channel with no runtime.
* `leave/2` on a channel with no runtime returns `{:error, :not_running}`. Do not
  resurrect a process just to remove somebody from it.
* Connected users are deduplicated by id. A user with two tabs counts once here;
  multi-device presence is Track 2's problem.
* `get_or_start/2` accepts `idle_timeout: milliseconds` so the shutdown behavior
  is testable without sleeping. Pick your own default for `get_or_start/1`.
* "Idle" means nobody is connected. A runtime with a connected user stays up
  regardless of how long it has been quiet.
* An idle shutdown must exit with a reason a supervisor considers normal.
* `stop/1` is idempotent, returns `:ok` even if nothing was running, and the
  runtime must stay stopped afterwards.

## Design questions

### 1. How is a runtime found by `channel_id`?

`Registry` is the answer, but there are decisions inside it.

* **Registry keys.** `:unique` or `:duplicate`? What does each one mean for
  "exactly one runtime per channel"?
* **What is the key?** The raw `channel_id`, or something namespaced like
  `{:channel, channel_id}`? The second costs nothing now and matters the moment a
  second kind of runtime process wants the same Registry.
* **`:via` tuples vs manual lookup.** You can register with
  `name: {:via, Registry, {registry_name, key}}` and then let
  `GenServer.call({:via, ...}, msg)` do the lookup for you on every call, or you
  can call `Registry.lookup/2` yourself and then `GenServer.call(pid, msg)`. The
  `:via` form is shorter and always re-resolves the name; the manual form lets you
  distinguish "no such process" from "process died mid-call" and gives you a place
  to decide whether to start one. Which do `whereis/1` and `join/2` each want?
* **Does the Registry need to be a module you write?** Look at what
  `{Registry, keys: :unique, name: SomeName}` gives you as a child spec before you
  write any code.

### 2. What prevents duplicate runtimes under concurrency?

This is the core of the lab.

Request A and request B both ask for channel 10 at the same instant. Both check
whether a runtime exists. Both see nothing. Both try to start one. In a language
where you would reach for a mutex, what does the BEAM give you instead?

Options, roughly in order of how much you should trust them:

* **Start first, handle the collision.** Call
  `DynamicSupervisor.start_child/2` unconditionally and pattern-match on
  `{:error, {:already_started, pid}}`. Where does that error come from — the
  supervisor, or the `:via` registration inside `GenServer.start_link/3`? Which
  process actually loses the race, and what happens to the loser's half-started
  GenServer? Cheap, no extra process, but you must be certain the guarantee is
  real rather than probable.
* **Look up first, then start, then look up again.** Optimizes the common case
  where the process already exists. But the second lookup is still racy against a
  process that is shutting down. Does the retry terminate?
* **Serialize through a single manager GenServer.** All `get_or_start` calls funnel
  through one process, so there is no race by construction. What is the cost when
  a thousand sockets join at once? What happens if the manager's mailbox backs up,
  or if the manager crashes?
* **A global lock.** `:global.trans/2` or similar. Almost certainly wrong here —
  be able to say why.

Then answer: is the guarantee you chose *actual mutual exclusion*, or merely a
narrow window? Track 4 will ask you the same question again across two nodes, and
the answer changes.

### 3. Which channels get a runtime, and when does one start?

The original plan warned against assuming every channel needs a process. Reason
about it concretely:

* A workspace with 5,000 channels, 12 of which anyone has opened today.
* A channel nobody has visited in a year.
* A user who opens a channel, reads two messages, and closes the tab.

Is a runtime created when the channel row is inserted, when the first client
joins, or on demand for any operation? What is a runtime actually *for* — if you
cannot name state that must live in it, it should not exist yet.

Also consider `init/1`. If `init/1` queries PostgreSQL to validate the channel or
load recent state, then `start_link/1` blocks until that query returns, and the
caller of `get_or_start/1` blocks with it. What happens under a slow database?
What is the default `GenServer.start_link/3` timeout, and what does
`handle_continue/2` offer you here?

### 4. Who decides that a runtime stops?

An idle runtime is wasted memory, but shutting one down is a lifecycle decision
with a race in it.

Mechanisms:

* A timeout in the GenServer's return tuple (`{:noreply, state, timeout}`), which
  arrives as `:timeout` in `handle_info/2`. Simple, but it resets on *every*
  message, not just meaningful ones. Is that what you want?
* An explicit `Process.send_after/3` timer you store and cancel yourself. More
  code, total control. Lab 05 will make you do this properly for typing
  indicators, so this is a preview.
* An external janitor process that periodically sweeps idle runtimes. Who owns the
  liveness information it needs?
* Monitoring the connected client processes so the runtime learns about departures
  it was never told about. Worth thinking about even if you do not do it yet:
  `leave/2` is only called when a client leaves *politely*.

Then the race: the runtime decides it is idle and begins shutting down, and a new
`join/2` arrives for that same channel microseconds later. Walk through it.
Does the joiner get `{:error, :noproc}`? A PID that is about to die? A stale
Registry entry? A brand-new process? What does the caller experience, and is that
acceptable? Sketch a fix, and be honest about whether it closes the window or just
shrinks it.

### 5. What restart strategy does a dynamically started runtime want?

* `:permanent`, `:transient`, or `:temporary` — say what each means for a process
  whose entire purpose is to hold state that is meaningless after a crash.
* What does `DynamicSupervisor` default to, and does that default match your
  intent?
* If the supervisor restarts a runtime, does it re-register in the Registry? Why
  does the answer depend on where the `:via` name lives?
* If your idle shutdown exits with a reason the supervisor considers abnormal, you
  have accidentally built a restart loop. Which exit reasons are "normal"?
* What is the state of a restarted runtime? Say it in one sentence, because it is
  the whole lesson of the phase.

### 6. Where do these go in the supervision tree?

`BeamSlack.Application` needs the Registry and the DynamicSupervisor added.

* Which order, and why does order matter for `:one_for_one`? What breaks if a
  runtime starts before the Registry exists?
* Is `:one_for_one` still right for the application supervisor now that two of its
  children depend on each other? What would `:rest_for_one` change?
* Should the Registry and the DynamicSupervisor sit directly under
  `BeamSlack.Supervisor`, or under an intermediate `BeamSlack.Runtime.Supervisor`
  that owns the whole subtree? What does the extra layer buy you when you want the
  runtime subsystem to fail as a unit without taking down `Repo` and `Endpoint`?

## Failure questions

Answer these in writing before you consider the lab done. Lab 09 will collect
them into a proper matrix.

1. One channel runtime crashes. What happens to the other runtimes? To the
   Registry entry? To the messages in PostgreSQL? To a client that was connected?
2. The `DynamicSupervisor` crashes. What happens to its children? Does the
   Registry know?
3. The `Registry` crashes. The runtimes are still alive — can anything reach them?
   Are they garbage now? Who cleans them up?
4. The whole BEAM node dies. What is lost, and what does a client observe when it
   reconnects?
5. `Repo` crashes but everything else survives. Can a runtime still serve
   `connected_users/1`? Should it be able to?

## Acceptance criteria

* `mix test.labs` passes.
* `mix precommit` passes (compile without warnings, format, Credo).
* The Registry and DynamicSupervisor are started by the application, and
  `iex -S mix` lets you call `ChannelRuntime.join/2` with no manual setup.
* No caller outside the `BeamSlack.Runtime` namespace handles a PID.
* You have written answers to the failure questions above, and you can defend your
  answer to design question 2 when Track 4 attacks it across two nodes.

Tests worth adding yourself, because they encode decisions only you have made:

* The behavior you chose for the shutdown-versus-join race.
* The restart behavior implied by your restart strategy — either that a crashed
  runtime comes back on its own, or that it stays dead until someone asks for it
  again.

## Non-goals

* No database access from the runtime. Keeping this lab DB-free is deliberate: the
  test suite is `async: true` and pure OTP. Validating that a `channel_id` exists
  is Track 2's problem.
* No PubSub, no broadcasting, no Presence. Track 2.
* No message history in the runtime. Messages are durable state and live in
  PostgreSQL. The runtime holds only what is meaningless after a crash.
* Not distributed. Track 4 breaks this deliberately.

## Hints

* `Registry` has `lookup/2`, `keys/2`, `count/1`, and `select/2`. Read the
  moduledoc's "Using in `:via`" section.
* `DynamicSupervisor.start_child/2` returns `{:ok, pid}`, `{:ok, pid, info}`,
  `:ignore`, or `{:error, reason}`. Read what `reason` can be. The
  `{:already_started, pid}` shape is the one to study.
* `GenServer.start_link/3` with a `:name` that is already taken does not raise; it
  returns. Find out exactly what.
* To make the concurrency test bite, do not just spawn tasks in a loop — have them
  all block on the same signal first, so they collide on purpose.
* `Process.monitor/1` plus `assert_receive {:DOWN, ref, :process, pid, reason}` is
  how you observe a shutdown in a test. `Process.sleep/1` is not.
