# Lab 09 — The Failure Matrix

Track 3. Concepts: attribution. Which layer actually recovered, and how you know.

This lab has no tests and no code. It is a document, and it is the most valuable
artifact in the project.

## The problem

By now you have several recovery mechanisms stacked on top of each other:

* OTP supervisors restarting crashed processes
* Phoenix Channels rejoining and replaying
* the JavaScript client reconnecting its WebSocket with backoff
* DBConnection reconnecting to PostgreSQL with its own backoff
* Phoenix.Presence's CRDT converging after a disruption
* PostgreSQL itself, keeping data that no BEAM process could

When you kill something and the app keeps working, it is extremely easy to
attribute that to the wrong layer. "OTP restarted it" is the satisfying answer and
is frequently not what happened — the client reconnected, or the query was
retried, or nothing was broken in the first place because the state was in
PostgreSQL all along.

Getting this wrong is expensive later, because you will design as though a layer
protects you when it does not.

## The method

For each injected fault, answer the same seven questions. Write the prediction
*first*, then run it, then write what actually happened. The gap between those two
columns is the entire point of the exercise; a matrix filled in after the fact
teaches almost nothing.

1. **What died?** The specific process or resource, named.
2. **Who noticed?** Which process received the exit signal, `:DOWN`, or error, and
   how did it find out?
3. **What restarted it, if anything?** Name the supervisor, or the reconnect loop,
   or say "nothing".
4. **How long?** Rough wall-clock time until the system was serving normally.
5. **What state was lost?** Be specific. "Presence" is not specific; "the metas for
   every user on this node, until each client's next join" is.
6. **What did the user see?** Open a browser tab and look. Nothing, a stall, an
   error, a reconnect banner, missing messages?
7. **Which layer actually recovered it?** OTP, Phoenix, the client, PostgreSQL, or
   nothing-was-broken. Justify it: what evidence distinguishes your answer from the
   others?

Question 7 is the one that matters, and question 6 is how you keep yourself honest
about question 7.

## The faults

Fill in a row for each. `docs/failure-matrix.md` has the template.

| # | Fault | How |
| --- | --- | --- |
| 1 | Kill a channel runtime with users connected | `mix beamslack.kill` after adding it as a target, or from IEx |
| 2 | Kill the Presence tracker | `mix beamslack.kill presence` |
| 3 | Kill PubSub | `mix beamslack.kill pubsub` |
| 4 | Kill the Endpoint | `mix beamslack.kill endpoint` |
| 5 | Kill the Repo | `mix beamslack.kill repo` |
| 6 | Drop every database connection | `curl -X POST localhost:4000/dev/faults/db` |
| 7 | Stop PostgreSQL entirely | `docker compose stop postgres`, then start it again |
| 8 | Kill one socket process | from IEx, find one on the dashboard's Processes page |
| 9 | Flood a process past its drain rate | `mix beamslack.flood --count 100000` |
| 10 | Kill the ETS owner from Lab 07 | see that lab |
| 11 | Kill the Watcher from Lab 06 with watches outstanding | see that lab |
| 12 | Kill the whole VM | `kill -9` the beam, then restart |

For every one of them, have a browser tab open on a channel, and have
`mix beamslack.loadtest --clients 20 --rate 2 --duration 60` running in another
terminal so there is actual traffic. A fault injected into an idle system tells
you much less.

## What to look for

**Fault 2 is the interesting one.** `mix beamslack.kill presence` takes down the
entire application, and the reason is worth chasing to the bottom: the registered
name points at a supervisor inside the Presence subtree, its restart races with
the previous shard's shutdown, the restart fails with `already started`, that
counts as a restart, and three of those inside the default `max_restarts` window
propagate all the way to the top. Nothing there is a bug. It is what "restart"
means when a restart outruns a shutdown, and it is why `max_restarts` exists.

You will only see that chain if supervisor reports are enabled. They are, in
`config/dev.exs` — read the comment there, then try turning them off and killing
Presence again, and notice that the log shows you a single crash and then silence
while the application dies.

**Faults 5 and 6 should differ**, and if they do not, you have found something.
Killing the Repo restarts a supervisor; dropping connections exercises
DBConnection's own reconnect with backoff underneath a Repo that never noticed.
Different layer, different timing, different user experience.

**Fault 7 is the one that takes real time.** Watch the queue times climb in the
logs — `db pool saturated` is logged specifically for this — before anything
errors. Also notice how much of the app keeps working while the database is gone,
and what that tells you about where state lives.

**Fault 12 is the control.** Nothing in the BEAM helps. What comes back, and from
where? That is your definition of durable, empirically established.

## Acceptance criteria

* `docs/failure-matrix.md` filled in for all twelve faults, with the prediction
  column written before each run.
* At least two rows where your prediction was wrong, and a sentence on why. If
  there are none, you filled it in afterwards.
* A closing paragraph answering: which layer does the most work, and which one did
  you *think* was doing the most work before you started?

## Non-goals

* No fixes. This lab is diagnosis only. If a fault reveals something you want to
  change, note it and keep going; changing the system mid-matrix invalidates the
  rows above it.
* No chaos automation. Twelve faults by hand, watched, is the exercise.
