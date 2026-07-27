# Lab 07 — ETS Ownership and the Heir

Track 3. Concepts: ETS tables, atomic counters, table ownership, `heir`,
`:ets.give_away/3`, `{:"ETS-TRANSFER", ...}`, when shared mutable state is correct.

## The problem

A rate limiter is consulted on every message send. If its state lives in a
GenServer's state, every send in the system is serialized through one mailbox, and
the thing meant to protect you from overload becomes the bottleneck that produces
it. This is not hypothetical: it is the single most common way an Elixir system
accidentally builds a global lock.

ETS is the answer to that. A table is shared memory that any process can read and
write directly, with no message passing. `:ets.update_counter/4` is atomic, so
fifty processes can increment the same counter at once and the arithmetic is still
right.

Then the catch, which is the lab: **an ETS table is owned by a process, and when
that process dies, the table is deleted.** Not orphaned. Not collected later.
Deleted, with everything in it, instantly. So the natural design — a GenServer that
creates a table in `init/1` — has a rate limiter that forgets every limit at
exactly the moment things are going wrong.

## What already exists

`BeamSlack.Runtime.RateLimiter` at `backend/lib/beamslack/runtime/rate_limiter.ex`
is a skeleton whose every function raises. Tests are at
`test/beamslack/runtime/rate_limiter_test.exs`.

The LiveDashboard has an ETS page listing every table with its size, memory, and
owner. Keep it open.

## The contract

* `hit(key, opts)` → `{:ok, remaining}` or `{:error, :rate_limited, retry_after_ms}`
* `remaining(key, opts)` → integer, without consuming
* `reset(key)`, `reset_all()` → `:ok`
* `table()` → the table name or reference, for inspection

`opts` carries `:limit` and `:window_ms`; your defaults should read
`Application.get_env(:beamslack, :rate_limit)`.

The two hard requirements are in the tests: fifty simultaneous callers against a
limit of ten must produce exactly ten successes, and the limiter must still work
after its owning process is killed.

## Design questions

### 1. Why is check-then-write wrong?

Write out the interleaving for two processes doing `lookup`, then `insert`, at a
limit of 1. Both read 0, both write 1, both proceed. Nothing about ETS prevents
this, because ETS gives atomicity *per operation*, not across a sequence.

`:ets.update_counter/4` is one operation and returns the new value, which is why
the contract makes `hit/2` a single call. Read its docs including the four-argument
form with a default, then say what would happen without the default — the very
first hit for a key, when there is no row yet.

### 2. The table's type and access

`:set`, `:ordered_set`, `:bag`, `:duplicate_bag`. `:public`, `:protected`,
`:private`. `read_concurrency`, `write_concurrency`, `decentralized_counters`.

Pick each one deliberately:

* If the table is `:protected`, who can write? Does that force writes through a
  process, and does that undo the entire point?
* `read_concurrency: true` optimizes for many readers and few writers, and
  actively costs when reads and writes interleave. Which is this workload?
* `decentralized_counters: true` exists for exactly the case of many processes
  updating counters. Read what it trades away.

### 3. How is the window represented?

**A fixed bucket.** Key on `{user_id, div(now, window)}`. Trivially atomic, and a
user can send `2 * limit` messages across a bucket boundary. Is that acceptable?

**A sliding log.** Store every timestamp and count the ones inside the window.
Exact, and memory grows with traffic — which is a bad property for the mechanism
you rely on when traffic is the problem.

**Token bucket.** A count and a last-refill time, refilled on read. Smooth and
correct, and now `hit/2` is a read, an arithmetic step, and a write, which is not
one atomic operation. Can you get it back to one? (Look at what
`:ets.update_counter/4` accepts as its third argument, and at `:ets.select_replace/2`.)

The tests accept any of these. Choose, and be able to say what your choice's worst
case looks like.

### 4. Who owns the table, and does it have an heir?

**Created in a GenServer's `init/1`, no heir.** Owner dies, table dies, every count
is lost, and the next call crashes with `ArgumentError` until the supervisor
restarts the owner and it recreates the table. The tests forbid the crash.

**Created by a long-lived owner that does nothing else.** A process that only holds
tables is very unlikely to crash, because it runs no code that can. This is a real
pattern and it feels like cheating, which is worth thinking about.

**An heir.** `:ets.new(name, [heir: pid, heir_data])` names a process to inherit the
table when the owner dies. The heir receives `{:"ETS-TRANSFER", table, from_pid,
heir_data}` and must handle it — an unhandled `handle_info/2` clause crashes the
heir, and now the table is gone anyway *and* you have taken down a second process.

**A supervisor as heir.** Tempting, since supervisors are the most reliable
processes around. But a `Supervisor` does not have a `handle_info/2` you can
implement, so what actually happens to that message?

Decide, and then answer the harder question: after the owner is restarted and the
heir holds the table, how does the new owner get it back? What happens if it does
not, and simply creates a new table with the same name?

### 5. Should the counts survive at all?

A rate limiter that forgets on restart is defensible; the window is short and the
consequence is bounded. A rate limiter that *crashes* on restart is not. The tests
enforce only the second. Say which you built and why, because "it survives" is a
cost, not automatically a benefit.

## Failure questions

1. The owner is killed with `:kill`. What is the exact sequence of events for the
   table, the heir if any, and the supervisor? What does a concurrent `hit/2`
   during that window observe?
2. A process reads the table while the owner is being killed. Does it get a stale
   value, an error, or a crash? Which error, exactly?
3. Ten thousand keys accumulate and nothing removes them. When does that become a
   problem, and what removes them? Is the cleanup a periodic sweep, a read-time
   check, or a second table you swap out? What does each cost?
4. The heir process dies before the owner. What is the table's heir now?
5. Track 4 preview: this table is node-local. Two nodes each enforce a limit of 10
   independently. What is the effective limit, and is that a bug?

## Acceptance criteria

* `mix test.labs` passes for `test/beamslack/runtime/rate_limiter_test.exs`,
  including the concurrency and owner-death tests.
* The table appears on the LiveDashboard ETS page and you can name its owner.
* You have killed the owner with `mix beamslack.kill` while the load test is
  running and watched what happens.
* A written answer to question 5, since it decides whether this design survives
  Track 4.

## Non-goals

* Do not wire the limiter into the message path yet. Get it right in isolation;
  Lab 08 is where flow control meets the real path.
* No distributed limiting.
* No persistence. If you want a limit that survives a node restart, you want
  something other than ETS, and saying which is enough.

## Hints

* `:ets.info(table, :owner)` and `:ets.info(table, :heir)` are how the tests find
  the owner, and how you should check your assumptions in IEx.
* `:ets.whereis(name)` returns the table identifier for a named table, or
  `:undefined`. Useful for "does it exist right now" without rescuing an
  `ArgumentError`.
* A named table's name is released when the table is deleted, so recreating it
  works — which is precisely why the "forgot everything but did not crash" outcome
  is easy to reach by accident. Make sure you know which outcome you built.
* `:persistent_term` is the other shared-state primitive, and it is the wrong tool
  here. Read why: what does a write to `:persistent_term` do to every process in
  the VM?
