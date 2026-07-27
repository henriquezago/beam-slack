# Lab 10 — Finding a Process on Another Node

Track 4. Concepts: `Node.connect/1`, node-local name registration, `:global`,
`:pg`, singleton processes in a cluster, why "just use a Registry" stops working.

## The problem

Everything you have built so far assumes one node. Lab 01's `ChannelRuntime` finds
a channel's process through a `Registry`. That works perfectly, and it works
perfectly *per node*, because a `Registry` is an ETS table on the node that created
it and there is no version of it that is not.

So with two nodes running:

* a user on node A opens `#general` and a runtime starts on A
* a user on node B opens `#general`, B's registry is empty, and a second runtime
  starts on B
* both are alive, both hold state for the same channel, and neither knows about
  the other

Nothing warns you. `Registry.lookup/2` returning `[]` on node B is indistinguishable
from "not started yet", which is exactly the answer that makes you start another
one. Same for `Process.whereis/1` and a named `GenServer`: names are node-local, and
`nil` on the wrong node looks like `nil` after a crash.

Watch it happen before reading further:

```
bin/dev-node.sh a
bin/dev-node.sh b
mix beamslack.cluster connect
mix beamslack.cluster check
```

The `check` output compares `registry_keys` on both nodes. Once Lab 01 is
implemented, start a runtime on one node and run it again.

## Why messages still work

This is the confusing part, and it is worth being precise about. With the nodes
connected, a message sent in `#general` on node A *does* reach a browser connected
to node B. `mix beamslack.cluster check` proves it.

That happens because `Phoenix.PubSub`'s PG adapter forwards broadcasts to the other
node's adapter, which delivers to its local subscribers. Presence works for a
related reason: it replicates a CRDT over that same PubSub. Both of those were
written by someone else to be distributed, and you got them for free.

Nothing you wrote is distributed. The distinction matters because it means "it
works across nodes" is not evidence of anything about your code.

## What already exists

* `bin/dev-node.sh` and `bin/dev-cluster.sh` start named nodes
* `mix beamslack.cluster` shows status, connects, checks, partitions, and heals
* `BeamSlack.Dev.Cluster.inventory/0` reports what each node can see locally
* `GET /api/health` returns the node name and its connected peers, and the
  HealthBadge in the UI shows which node a browser session is on

## The exercise

### Part 1 — Do it by hand first

In an IEx session on each node (`bin/dev-node.sh` runs `mix phx.server`; use
`iex --sname beamslack_c --cookie beamslack -S mix` for a third):

* `Node.self/0`, `Node.list/0`, `Node.connect/1`, `Node.disconnect/1`
* `:erpc.call(other, Node, :self, [])` — a function call with a node in front of it
* spawn a process on the other node and send it a message. Notice there is no
  serialization step, no schema, no client library. A pid is a pid.
* `Node.monitor(other, true)`, then stop the other node, and read the message

Then answer: what is the cookie for? What happens with mismatched cookies, and what
does the error look like? Is distributed Erlang's security model something you would
put on a public network?

### Part 2 — The discovery problem

Registration options, in the order you should consider them:

**`Registry`.** Node-local. Fast, ETS-backed, no coordination. Already in use, and
already the source of the bug above.

**`:global`.** A cluster-wide name registry in OTP. `:global.register_name/2`,
`:global.whereis_name/1`, and it works with `{:via, :global, name}` so a GenServer
can use it with a one-line change. What it costs: registration is a synchronous
global lock across every node, which does not scale with cluster size, and after a
partition heals two nodes may each hold the same name — `:global`'s resolver is
called and by default one of the processes is *killed*. Find out which one.

**`:pg`.** Process groups, eventually consistent, no global lock. A group can have
many members, so it is a natural fit for "every node's runtime for this channel"
but not for "exactly one runtime". It does not resolve conflicts because it does
not consider them conflicts.

**A consistent-hash ring.** Each channel id hashes to a node; whoever wants the
runtime asks that node. No coordination at all, and the answer is stable as long as
every node agrees on the membership list. When a node joins or leaves, some
channels move, and two nodes briefly disagree about who owns what. This is what
Horde and Swarm do, with more machinery around handoff. You are not building one,
but you should be able to sketch it, because it is the design that actually scales.

**Do not distribute the process at all.** Let each node have its own runtime for the
same channel, and make sure the runtime holds nothing that would be wrong if
duplicated. Presence already works this way and it is not a compromise — it is a
better design when the state is genuinely mergeable. Ask honestly what
`ChannelRuntime` holds that cannot tolerate duplication. If the answer is
"the typing timers", is that worth a global lock?

### Part 3 — Pick one and argue it

Write it down: which mechanism, why, what it costs, and what breaks under a
partition. You do not have to implement it — Lab 12 will make you predict its
behavior when the network splits, and an implementation you have to defend is worth
more than one you can hide behind.

If you do implement `:global`, the change to Lab 01 is small and the tests should
still pass, since they only use the public API. That is a good sign about the API.

## Failure questions

1. `Registry.lookup/2` returns `[]` on node B while a runtime is alive on node A.
   What does your `get_or_start/1` do? What *should* it do?
2. Two runtimes for the same channel exist on two nodes. What is actually broken?
   Enumerate the state, item by item, and mark each as harmless-if-duplicated or
   not. This is the most useful thing in this lab.
3. A pid from node A is held on node B and node A dies. What does `Process.alive?/1`
   say about it? (Careful. Read the docs on remote pids before answering.)
4. `:global.register_name/2` is called on two nodes simultaneously for the same
   name. What happens, and what does the loser receive?
5. `:erpc.call/4` to a node that has become unreachable. How long before it
   returns, and what does it return? Which timeout governs it — yours, or
   `net_ticktime`?

## Acceptance criteria

* Two nodes running, connected, with a browser on each, and you can say which node
  each browser is talking to without guessing.
* You have demonstrated the duplicate-runtime bug and can show it in
  `mix beamslack.cluster check` output.
* A written decision for Part 3, with the partition behavior of your choice stated
  in advance. Lab 12 checks it.

## Non-goals

* No Horde, no Swarm, no libcluster. Automatic clustering hides the handshake you
  are here to see; two terminals and `Node.connect/1` is the point.
* No cross-node handoff of live state.
* Do not change PubSub or Presence. They already work; understanding *why* is the
  assignment.

## Hints

* `:erpc.call/4` replaced `:rpc.call/4`. The old one silently returns `{:badrpc,
  reason}` where the new one raises, which is why the tooling here uses `:erpc`.
* `Node.monitor(node, true)` gives you `{:nodedown, node}`. That is the only
  reliable notification a node is gone — and Lab 12 will show you how long "gone"
  takes to establish.
* `:global.sync/0` blocks until the global name table has converged. Its existence
  tells you the table is not always converged.
* `:net_kernel.get_net_ticktime/0` is 60 seconds by default, and a peer is declared
  down after roughly four tick intervals of silence. Every distributed-system
  surprise in this project traces back to that number.
