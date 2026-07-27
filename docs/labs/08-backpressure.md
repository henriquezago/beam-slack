# Lab 08 — Backpressure

Track 3. Concepts: unbounded mailboxes, `call` versus `cast`, load shedding,
bounded queues, where overload pain should land.

## The problem

Every BEAM process has an unbounded mailbox. `send/2` always succeeds, always
returns immediately, and never tells you the receiver is behind. There is no
built-in limit, no rejection, and no signal. A producer faster than its consumer
will therefore consume all available memory, and the first symptom is usually not
the flooded process failing — it is the whole VM degrading as garbage collection
walks a gigantic heap that is almost entirely one process's mailbox.

Go see it before reading further:

```
mix beamslack.flood --count 50000 --watch
```

That is `BeamSlack.Dev.FloodTarget`, which is wrong on purpose. Nothing about it
crashes. It just falls behind forever.

## The uncomfortable part

You cannot fix this with `send/2`, because `send/2` has no failure mode. So
backpressure must come from somewhere else, and there are only three real
somewheres:

* **The sender waits.** If the producer blocks until the consumer responds, its
  rate is capped by the consumer's. This is what `GenServer.call/3` does, and it is
  the reason a `call` is not merely a `cast` that returns a value: a `call` is a
  flow-control mechanism that happens to also return a value.
* **The receiver refuses.** The process inspects its own backlog and rejects new
  work, or drops old work. It has to be able to measure the backlog, which means
  the backlog cannot be the mailbox — you can read `message_queue_len` but you
  cannot decline a message that has already arrived.
* **Something in between buffers.** A bounded queue that producers must get past.
  This is what GenStage and Broadway are, underneath.

Every one of these moves the pain rather than removing it. The design question is
where you want it: latency for the producer, dropped work, or a rejection the
producer has to handle.

## What already exists

`BeamSlack.Runtime.Ingest` at `backend/lib/beamslack/runtime/ingest.ex` is a
skeleton whose every function raises. Tests are at
`test/beamslack/runtime/ingest_test.exs`. `BeamSlack.Dev.FloodTarget` is the
counterexample, and `mix beamslack.flood` and the dashboard are how you watch.

## The contract

* `submit(work, opts)` → `:ok` or `{:error, :overloaded, queue_len}`
* `queue_len()` → integer, and it must answer while saturated
* `stats()` → `%{accepted:, rejected:, completed:}`
* `reset()` → `:ok`

`opts` carries `:max_queue` and `:cost_ms`.

The two invariants the tests enforce:

1. **`accepted == completed + still queued`.** Accepting work and then dropping it
   is the one unacceptable outcome, because the caller was told it succeeded.
2. **The queue never exceeds `max_queue`, and neither does the mailbox.** There is
   a test for the mailbox specifically, because tracking a bound while still
   accepting every message into the mailbox is the most common way to appear to
   solve this.

## Design questions

### 1. `call` or `cast`?

**`cast`.** Returns immediately, never blocks the caller. And it is fire-and-forget,
so the caller cannot be told "no", which means it cannot be rejected, which means
the mailbox grows. A `cast` cannot implement this contract's return type. Sit with
why for a moment: the return type of `submit/2` has already ruled something out.

**`call`.** The caller waits for a reply, so the producer's rate is bounded by the
consumer's. Now: what happens when the consumer is 2,000 units behind and a caller
issues a `call` with the default 5,000ms timeout? The test
"the submitting process is never blocked for long" is about exactly this. What does
a `call` timeout do to the message that was already sent? (It does not cancel it.
Read `GenServer.call/3`'s docs on what arrives at the server after a timeout.)

**Neither.** Read a counter from ETS or `:atomics` before sending, and refuse
without talking to the consumer at all. Fast, and the counter can be wrong under
concurrency unless the increment is atomic — which is Lab 07's lesson reappearing.

### 2. Where does the queue live?

If the backlog is the mailbox, you cannot enforce a bound, because a message in
your mailbox has already been accepted. So either:

* the bound is checked *before* sending, by the caller, against shared state
* the intake is a separate lightweight process from the worker, holding an explicit
  queue in its state and passing work along one unit at a time
* the worker pulls, rather than being pushed to — the consumer asks for work when
  it is ready, which inverts the whole flow and is what GenStage's demand is

Sketch each one, and note which of them can honor "the mailbox is not where the
backlog lives".

### 3. Reject, shed, or wait?

**Reject the new work.** The newest request fails while older ones proceed. Simple,
and under sustained overload the callers who suffer are the recent ones — which
during a spike is most of them.

**Shed the oldest.** Drop from the front of the queue. Keeps latency low for what
survives, and violates invariant 1 unless you only shed work you never accepted.
Can you shed and still be honest? What would `submit/2` have to return?

**Make the caller wait.** No work is lost and the producer is slowed to the
consumer's rate. And if the producer is a Phoenix channel process, you have just
moved the queue into the socket, and from there into the client's network buffer.
Is that better? Sometimes genuinely yes. Say when.

### 4. What should a caller do with a rejection?

`{:error, :overloaded, queue_len}` gives the caller a number. What is it for? Retry
with backoff, show the user an error, drop silently? Note that a caller which
retries immediately on rejection has built a busy loop that makes the overload
worse. If you return a number, decide what you intend it to be used for.

### 5. Now apply it

This module is a standalone exercise, but the shape it is teaching applies directly
to the message path. If a channel with 5,000 subscribers receives 100 messages a
second, where is the queue? Which process's mailbox? What would rejecting look
like from a user's point of view, and is "your message was not sent" ever the right
answer?

## Failure questions

1. The consumer crashes with 500 units queued. What happens to them? Should
   `accepted == completed` still hold, and what would it take?
2. A producer is killed mid-`submit`. If `submit/2` is a `call`, what happens to
   the reply? Where does it go?
3. Two producers each submit at twice the drain rate. Do they get rejected fairly,
   or does one starve? Does your design have any notion of fairness at all?
4. `queue_len/0` is called while the intake is saturated. Trace exactly how it
   answers. If it involves the saturated process doing work, it will time out at
   the worst moment — and you will have reinvented `FloodTarget.stats/0`.
5. The overload ends. How long until the system is accepting normally again, and
   is there anything that makes recovery slower than it needs to be?

## Acceptance criteria

* `mix test.labs` passes for `test/beamslack/runtime/ingest_test.exs`, including the
  mailbox-length test.
* Running `mix beamslack.flood` against `FloodTarget` and comparing its behavior to
  `Ingest` under the same load, you can describe the difference in one sentence.
* You have written down which of the three places the pain lands in your design,
  and what a user would see.

## Non-goals

* Do not use GenStage, Broadway, or `:jobs`. Read what GenStage's demand mechanism
  does afterwards and note how much of it you reinvented — that comparison is the
  reward for doing it by hand.
* No distributed rate control.
* Do not fix `BeamSlack.Dev.FloodTarget`. It is the control group.

## Hints

* `Process.info(pid, :message_queue_len)` is how the test measures the mailbox, and
  how you should check your own design before running it.
* `:erlang.process_flag(:message_queue_data, :off_heap)` changes where mailboxes
  live and how GC treats them. It does not bound anything. Worth knowing it exists
  and knowing it is not the answer.
* A `GenServer.call/3` that times out still leaves the request in the server's
  mailbox, to be processed later, with a reply sent to a caller that has stopped
  listening. Under overload, that is work being done for nobody. This is the single
  most important sentence in this brief.
* `:atomics` and `:counters` are lock-free shared counters, cheaper than ETS for
  exactly this. Worth a look for the check-before-send design.
