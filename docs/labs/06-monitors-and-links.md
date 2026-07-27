# Lab 06 — Monitors, Links, and Who Dies With Whom

Track 3. Concepts: `Process.link/1`, `Process.monitor/1`, exit signals, trapping
exits, `:DOWN` messages, the demonitor race.

## The problem

Several things in BeamSlack need to know when a process they did not start has
died. A channel runtime has to drop a user whose socket vanished. A cache has to
invalidate an entry whose owner is gone. Track 4 will need to notice when a whole
node disappears.

None of that is supervision. A supervisor restarts processes it started; this is
about processes you merely care about. The BEAM offers exactly two primitives for
one process learning about another's death, they behave very differently, and
choosing wrong produces a bug that only appears when something crashes — which is
to say, in production.

## The two primitives

**A link is bidirectional and lethal.** `Process.link(pid)` means "we share a
fate". When either dies abnormally, the other receives an exit signal and, by
default, dies too, propagating outward until it hits a process that traps exits.
Links cannot be counted: linking twice and unlinking once removes the link.
Supervision is built entirely on links plus `trap_exit`.

**A monitor is unidirectional and inert.** `Process.monitor(pid)` returns a
reference and sends the caller `{:DOWN, ref, :process, pid, reason}` when the
target dies. The monitored process learns nothing and is unaffected. Monitors are
counted: monitoring twice delivers two `:DOWN` messages. And a monitor on an
already-dead process fires immediately with `:noproc` rather than erroring, which
closes a race you would otherwise have to handle by hand.

`Process.flag(:trap_exit, true)` converts incoming exit signals into
`{:EXIT, pid, reason}` messages, turning a link from lethal to informative — but
it converts *all* of them, including from your supervisor, so a process that traps
exits has taken on the responsibility of shutting itself down properly. It is not
a way to make a link behave like a monitor; it is a different set of obligations.

The one signal nothing can trap is `:kill`.

## What already exists

`BeamSlack.Runtime.Watcher` at `backend/lib/beamslack/runtime/watcher.ex` is a
skeleton whose every function raises. The test suite is
`test/beamslack/runtime/watcher_test.exs`, and it expects the module to be running
under a name — so it also has to be in the supervision tree, which is yours to
arrange.

`mix beamslack.kill` and the LiveDashboard Processes page are how you look at this
from the outside.

## The contract

* `watch(pid, meta)` — begin observing, returns `:ok`
* `unwatch(pid)` — stop observing, and guarantee nothing arrives afterwards
* `watched()` — `[{pid, meta}]` of live watches
* `subscribe(pid)` — register for `{:process_down, pid, meta, reason}`

Watching a dead process must still notify. Silence is not an acceptable answer,
because a caller who gets silence cannot distinguish "alive" from "died a
microsecond ago", and that ambiguity is the source of most leaked state.

## Design questions

### 1. Monitor or link?

The suite settles this by killing watched processes and asserting the watcher is
still alive, so you already know the answer. What you should be able to do is
argue it: describe precisely what would happen with links and no `trap_exit`,
then with links and `trap_exit`, and say what the second one costs. In particular,
with `trap_exit` on, what happens when your supervisor tries to shut you down?

### 2. One process or one per watch?

**One named watcher.** Simple, one place to look, `watched/0` is trivial. But it
is a single point of failure holding everyone's watches, and its mailbox is shared
by every death in the system.

**A process per watch.** Isolated and naturally concurrent, and each one can be
linked to the watcher's supervisor. But now there are as many processes as watches,
and `watched/0` requires a registry.

**No process at all** — every caller monitors directly. Fewest moving parts and no
bottleneck, and honestly the right answer for a lot of real code. Say why it does
not satisfy this contract. (Hint: `watched/0`, and who receives the `:DOWN`.)

### 3. The demonitor race

One test kills a process and *then* unwatches it. By the time `unwatch/1` runs,
the `:DOWN` may already be sitting in the watcher's mailbox, and cancelling the
monitor does not remove a message that was already delivered.

`Process.demonitor(ref, [:flush])` handles it. Read the docs for what `:flush`
actually does, then answer: why is `:flush` not the default? What would it cost a
caller that has already handled the `:DOWN`?

### 4. What about the subscriber?

`subscribe/1` takes a pid, and that pid can die. If your watcher holds a
subscriber list and sends to it forever, you have built the leak this module was
supposed to prevent, one level up. So: does the watcher monitor its subscribers?
Notice that answering "yes" means the watcher watches things in two different ways,
and ask whether that is a smell or just the truth.

### 5. When is a link actually right?

Argue for links in a case from this codebase. A good candidate: a `Task` spawned to
do work on behalf of a request, where the caller has no use for the result if it
crashed and no use for continuing if the caller is gone. What does `Task.async/1`
use, and why does `Task.Supervisor.async_nolink/2` exist?

## Failure questions

1. A watched process exits with `:normal`. Is that a death worth reporting? The
   suite says yes — argue whether it should.
2. A process is watched twice with different metadata. How many notifications
   arrive? Is your answer a decision or an accident of the implementation?
3. The watcher's supervisor restarts it. Every watch is gone and nobody knows.
   What should happen, and can anything be done about it, or is this simply what
   "ephemeral" means?
4. A watched process is on another node and the network partitions. What reason
   arrives in the `:DOWN`, and how long does it take? (`:net_kernel`'s tick has an
   opinion. Track 4 tests it.)
5. Ten thousand processes are watched, and all of them die in the same second.
   What does the watcher's mailbox look like, and what does that have to do with
   Lab 08?

## Acceptance criteria

* `mix test.labs` passes for `test/beamslack/runtime/watcher_test.exs`.
* `BeamSlack.Runtime.Watcher` is in the supervision tree, and
  `mix beamslack.kill --list` can find it (add it to the target map).
* You can state, without checking, what happens to a linked process when its
  partner exits with `:normal`, with `:shutdown`, and with `:kill`, both trapping
  and not trapping exits. That is nine answers. Three of them surprise people.

## Non-goals

* Do not restart anything. A watcher that restarts is a supervisor, and a badly
  written one.
* No cross-node watching yet.
* Do not wire this into the channel or presence code as part of this lab. Get it
  right in isolation first; Lab 04's cleanup can use it afterwards if you want.

## Hints

* `Process.monitor/1` on a dead pid does not raise. It fires immediately with
  reason `:noproc`. One test depends on this, and it is the reason monitors are
  race-free in a way that "check if alive, then monitor" never is.
* `spawn(fn -> :ok end)` is dead almost immediately, which is how one test gets a
  reliably-dead pid.
* When something exits from a `raise`, the reason is `{exception, stacktrace}`, not
  the exception. A test matches on that shape.
* If you find yourself writing `Process.alive?/1` before doing something, stop.
  Between the check and the action, the answer can change. That function is almost
  never the right tool outside of tests.
