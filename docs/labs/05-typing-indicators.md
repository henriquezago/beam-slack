# Lab 05 — A Timer State Machine by Hand

Track 2. Concepts: `Process.send_after/3`, timer references and cancellation,
per-key timers in process state, why "expire in N seconds" is not a `sleep`.

## The problem

"Alice is typing…" has to disappear on its own. Alice does not send a
"stopped typing" event — she got distracted, or closed her laptop, or her network
dropped. The indicator has to expire without anyone telling it to.

The naive version is a keystroke that schedules a message to yourself three
seconds out, and when it arrives you broadcast that typing stopped. That is
correct exactly once. On the second keystroke it is wrong, and the wrongness is
the lab: you now have two timers pending, the first fires while Alice is still
typing, and the indicator flickers off and back on. Everyone writes this bug once.

You are building this by hand rather than reaching for a library because the
pattern — a map of keys to timer references, cancel-then-reschedule, and a `:DOWN`
or expiry message that has to handle a key that is already gone — is the same
pattern behind session timeouts, debouncing, rate limit windows, circuit breaker
half-open states, and idle process shutdown. You already met it in Lab 01's idle
shutdown. This is the multi-key version.

## What already exists

`ChannelChannel.handle_in("typing", ...)` raises, and so does the
`handle_info/2` clause reserved for expiry. Both are yours.

`config/config.exs` sets `:typing_timeout` to 3000ms and `config/test.exs`
overrides it to 100ms so the tests do not take a minute. Read it with
`Application.get_env(:beamslack, :typing_timeout)` rather than hardcoding, or the
tests will be slow and you will be tempted to make them sleep.

The React side is done: `MessageComposer` pushes `"typing"` on keystrokes
(throttled), and `TypingIndicator` renders whoever the `useChannelRealtime` hook
currently believes is typing based on `"typing_started"` and `"typing_stopped"`.

## The contract

* Client pushes `"typing"` with an empty payload. No reply.
* You broadcast `"typing_started"` with `%{user_id: id, name: name}`.
* After the timeout with no further keystroke, you broadcast `"typing_stopped"`
  with at least `%{user_id: id}`.
* Repeated keystrokes must not produce repeated `"typing_stopped"` broadcasts.
  There is one per typing burst.
* Each user expires independently. One user's expiry must not cancel another's.

Whether every keystroke re-broadcasts `"typing_started"` or only the first one in
a burst is yours to choose. The client tolerates both. One of them sends far more
traffic; the other requires you to know whether the user was already typing.

## Design questions

### 1. Which process holds the timers?

**The socket's channel process.** One process per connection, so its state holds
only its own user's timer — a single `timer_ref`, not a map. Simple. But a user
with two tabs has two independent timers broadcasting about the same person, and
the channel process has no idea who else is typing, so "only broadcast started if
they weren't already typing" is impossible to implement.

**`ChannelRuntime`, one process per channel.** Now one process holds
`%{user_id => timer_ref}` and knows the whole channel's typing state, so
deduplication and "who is typing right now" queries both work. This is the
version the lab title assumes and the one worth writing. It also means every
keystroke from every user in the channel is a message to one process — remember
that when Track 3 floods a mailbox.

**Neither; derive it from Presence metas.** Update a `typing_at` timestamp in the
meta and let clients decide. No timers at all. What breaks? Specifically: what
tells a client to re-render when nothing new arrives, and how big are the metas
now?

Whichever you choose, Lab 04's question 5 applies: if the process holding the
timers dies, what does the UI show, and for how long?

### 2. The cancellation

The core of it, in the runtime version:

* keystroke arrives for user `U`
* if `state.timers[U]` exists, cancel it
* schedule a new one, store the new reference
* on expiry for `U`, delete the entry and broadcast

Get precise about the cancel:

* `Process.cancel_timer/1` returns the remaining milliseconds, or `false` if the
  timer already fired or was already cancelled. When can `false` happen here, and
  what must your expiry handler tolerate as a result?
* There is a race even with cancellation: the timer fires and the message is
  already in your mailbox when you cancel it. `Process.cancel_timer/2` has an
  `:async` and an `:info` option, and `Process.cancel_timer(ref, info: false)`
  behaves differently again. Read the docs and decide what you need.
* Suppose you skip cancelling and instead store a monotonically increasing token
  per user, ignoring expiry messages whose token is stale. That also works. Which
  is better, and what is the tradeoff? (Hint: what accumulates?)

### 3. Storing the reference

`%{user_id => timer_ref}` is the obvious shape. Alternatives:

* `%{user_id => {timer_ref, started_at}}` if you want to answer "how long have
  they been typing"
* two maps, one keyed by ref for the expiry lookup, if the expiry message did not
  carry the user id. Does it need to? You control what you put in it.

What is the memory cost of a channel where 200 people are typing? Is there any
reason to bound this map?

### 4. What does an expiry message look like?

`send_after(self(), {:typing_expired, user_id}, timeout)` is one option, and
`send_after(self(), :typing_expired, timeout)` with the user id looked up from
state is another. The second one cannot work for multiple users; convince yourself
why before writing the first one, because the reason generalizes.

## Failure questions

1. The process holding the timers crashes while three users are typing. What do
   clients show, and for how long? Is there anything that fixes it besides the
   next keystroke?
2. A user closes their tab mid-burst. Does `"typing_stopped"` still fire? Which
   process's death, if any, is involved, and does the indicator clear because of a
   timer or because of a disconnect?
3. The system clock jumps forward an hour. Does `Process.send_after/3` care? Should
   you be using monotonic time anywhere here?
4. A user pushes `"typing"` 500 times in one second. How many timers exist at
   once? How many messages are in the mailbox? What is broadcast?
5. `refute_broadcast "typing_stopped"` in the test waits three timeout windows
   after the first stop. What implementation bug is that specifically catching, and
   why would a single `assert_broadcast` have missed it?

## Acceptance criteria

* `mix test.labs` passes for `test/beamslack_web/channels/channel_typing_test.exs`.
* In two browser tabs as different users: typing shows the indicator, stopping
  clears it after the timeout, and continuing to type keeps it up indefinitely
  with no flicker.
* No `Process.sleep/1` in your implementation. If you reach for one, the design is
  wrong.
* A written answer to question 1, because it is the same question as Lab 04's
  question 5 and your answers should agree.

## Non-goals

* No "typing in a thread" — threads land in Track 5.
* No persistence of typing state, ever. One of the tests asserts the database is
  still empty.
* Do not add a library for debouncing. Writing the state machine *is* the lab.

## Hints

* `Process.send_after/3` returns a reference and delivers a plain message; the
  channel receives it in `handle_info/2`. An unhandled `handle_info/2` clause
  crashes the process, which is exactly what one of the tests checks for.
* If you put the timers in `ChannelRuntime`, the channel process has to reach it,
  which means Lab 01's `get_or_start/1` and the broadcast has to come from the
  runtime rather than the socket. That is a real design consequence, not
  incidental — the runtime is not a `Phoenix.Channel`, so `broadcast!/3` is not
  available to it. What is?
* Lab 01's idle shutdown already made you write cancel-and-reschedule for one
  timer. Go read what you wrote there before starting; if it has the bug this lab
  is about, fix it there too.
