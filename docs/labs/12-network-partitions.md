# Lab 12 — Partitions, and Why There Is No Right Answer

Track 4. Concepts: split brain, CAP as a proof rather than a slogan, CRDT
convergence, `:global`'s name conflict resolution, what your Track 2 designs do
when the network splits.

## The problem

A crashed node is a solved problem: it stops, something notices, something else
takes over. A partition is different in a way that is not a matter of degree.

In a partition both halves are perfectly healthy. Both are serving users. Both
believe the other is gone. And from inside either half there is **no way, even in
principle**, to distinguish "the other node crashed" from "the network between us
broke". Not with a better algorithm, not with a longer timeout — the two situations
produce identical observations.

Every consistency trade-off follows from that single fact. You can keep serving and
accept that the halves will diverge, or you can stop serving until you can talk to
a majority. There is no third option, and any system that appears to have one has
quietly picked one of these two.

BeamSlack has already picked, several times, without asking you. This lab is about
finding out what it picked.

## Setup

```
bin/dev-node.sh a
bin/dev-node.sh b
mix beamslack.cluster connect
npm run dev:a     # browser on node a
npm run dev:b     # browser on node b
```

Log in as different users in each, same channel, confirm they see each other.

Then:

```
mix beamslack.cluster partition
```

Both nodes stay up. `mix beamslack.cluster heal` reconnects them.

One caveat, and it matters: `partition` uses `Node.disconnect/1`, which is a clean
break both sides notice immediately. A real partition is silent — packets stop
arriving and nobody notices until `net_ticktime` expires, up to four minutes later.
So run each experiment twice, once with `partition` and once with `kill -STOP` on
one node, and compare. The gap between "instantly" and "four minutes" is where the
genuinely nasty bugs live.

## The experiments

### 1. Messages

Send a message in each half.

* Does the other half see it? Immediately, eventually, or never?
* Both messages are in PostgreSQL, because both nodes share a database. So what,
  exactly, failed? Be precise: it is not the write.
* Reload each browser. Now what do they see, and what does that tell you about
  where the failure was?
* On heal: do the missed messages appear, and what makes them appear?

### 2. Presence

Watch the member list in each half while partitioned.

* Does each half still show the other's users? For how long?
* What number governs that? (`Phoenix.Tracker`'s `down_period`, not
  `net_ticktime`. Find both and note they differ.)
* On heal, do the lists converge? How long, and what is the mechanism?
* Was any presence information *wrong* at any point, or only incomplete? Those are
  different failures and the distinction matters.

Presence is an ORSWOT CRDT, which means it is designed to converge after exactly
this. Watching it work is the most satisfying part of this lab and worth reading
the `Phoenix.Tracker` source for.

### 3. Typing indicators

Type in each half while partitioned.

* Does the other half see it? What happens on heal — does a stale indicator appear,
  hang around, and eventually expire?
* Lab 05's timers are process-local. What does that mean during a partition, and is
  it a problem or is it the correct behavior for free?

### 4. Your Lab 10 decision

Whatever you chose for cross-node discovery, this is where it gets tested.

**If you kept the node-local `Registry`:** two runtimes for the same channel already
existed before the partition, so nothing changes. Is that resilience or is it that
you never had the property in the first place?

**If you used `:global`:** the singleton exists in one half. What does the other
half do when it needs it — start its own, or fail? Then, on heal, `:global` finds
two processes with one name and calls its conflict resolver. Read what the default
does. It kills one of them. Which one, and what happens to the state and the
callers of the process that dies?

**If you used `:pg`:** the groups diverge and then merge. Does anything reconcile
the members, or do you now have two of everything with no conflict to detect?

Whichever it was, you wrote a prediction in Lab 10. Compare.

### 5. The rate limiter

Lab 07's ETS table is node-local, which means it was never partition-tolerant — it
was never cluster-aware at all.

* With a limit of 10 and two nodes, what is the effective limit?
* Is that a bug? Under what circumstances is it fine, and under what circumstances
  is it a security problem?
* What would it take to fix, and what would that cost on every single request?

### 6. The heal

Run `mix beamslack.cluster heal` and watch both browsers.

* What converges automatically? Name the mechanism for each thing that does.
* What needs a reload?
* What is permanently wrong and will stay wrong? Look for it.
* How long did full convergence take, and which piece was slowest?

## The question this lab is actually about

For each piece of state in BeamSlack, answer: **during a partition, would you rather
it be available or consistent?**

| State | Available or consistent | Which did we build | Why |
| --- | --- | --- | --- |
| Message history | | | |
| Presence | | | |
| Typing indicators | | | |
| Channel membership | | | |
| Rate limits | | | |
| Channel runtime singleton | | | |

Fill it in. Most rows should be "available", and being able to say *why* that is
right for a chat application — and where it stops being right — is what this lab is
for. Then find the row where the answer would be different for a bank.

## Failure questions

1. Both halves accept a message at the same instant. Is there a conflict? Why not?
   What property of the data makes this safe, and would it hold for message
   *edits*?
2. A user is in both halves at once, on two devices. What does presence show
   during, and after? Is the after correct?
3. `:global` resolves a name conflict by killing one process. What happens to that
   process's callers, its links, and its state? Is there any way to hand off
   instead?
4. The partition lasts four hours. Does anything degrade differently than at four
   seconds? What accumulates? (Look at `permdown_period`.)
5. Three nodes, and one is cut off from the other two. Is that different from the
   two-node case? What could a majority do that a pair cannot, and does BeamSlack
   do anything with that?

## Acceptance criteria

* All six experiments run, both with `partition` and with `kill -STOP`, and the
  timing difference recorded.
* The availability-versus-consistency table filled in.
* A written comparison of your Lab 10 prediction against what actually happened.
* One paragraph: if BeamSlack were a payments system instead of a chat app, which
  design decisions in Tracks 1 through 4 would have to change?

## Non-goals

* No consensus. Do not add Raft, do not add a quorum. Know they exist, know what
  they buy, and know that a chat application is a poor place to pay for them.
* No conflict resolution beyond what Presence already does.
* No fixes. Diagnosis, prediction, and a written argument.

## Hints

* `Phoenix.Tracker`'s `down_period` (30s by default) is when a replica is
  considered temporarily down; `permdown_period` (20 minutes) is when its data is
  discarded entirely. Two very different behaviors, and experiments 2 and 6 hit
  different ones depending on how long you wait.
* `:global.sync/0` after a heal forces the name table to converge and will block
  until it does. Timing that block is informative.
* `Node.disconnect/1` on one side disconnects both, because distribution links are
  symmetric. There is no one-way partition in distributed Erlang without
  network-level tooling.
* If you want a genuinely silent partition rather than `kill -STOP`, `iptables` or
  `tc` can drop packets on the distribution port. That is beyond this lab, but the
  difference in what you observe is worth knowing about.
