# Lab 04 — Who Owns Presence

Track 2. Concepts: ephemeral distributed state, CRDTs, process monitoring as the
source of truth, `handle_info(:after_join, ...)`.

## The problem

"Who is in this channel right now" has no correct answer stored anywhere. It is not
in PostgreSQL, because a row saying `online: true` is a lie the moment a laptop
lid closes without a clean disconnect. The only authoritative signal is *is that
socket process alive*, which is knowledge the BEAM already has and PostgreSQL
never will.

`Phoenix.Presence` turns that into a data structure: an ORSWOT CRDT replicated
across nodes, keyed by topic, where each key holds a list of `metas` — one per
connection. Presence entries disappear when their tracking process dies, because
Presence monitors it. Nothing else has to clean up.

Your job is to decide whether that is your source of truth, and to make tracking
happen.

## What already exists

`BeamSlackWeb.Presence` in `backend/lib/beamslack_web/channels/presence.ex` is
`use Phoenix.Presence` boilerplate and is running under the supervision tree. It is
ready and tracking nothing.

`ChannelChannel.join/3` authorizes, then returns `{:ok, socket}`. It does not send
itself `:after_join`, and `handle_info(:after_join, socket)` raises. Both of those
are yours.

The React side is finished: `useChannelRealtime` maintains a `Presence` object
against `"presence_state"` and `"presence_diff"`, and `PresenceList` renders names
with a device count when a user has more than one connection. That component
already expects `metas` to carry a name — which is why one of the tests checks for
one.

## The contract

* Presence for channel `<id>` is listed under topic `"channel:<id>"`.
* Keys are user ids, as strings. Not socket ids, not membership ids.
* Each `metas` entry carries at least the user's `name`; `online_at` is
  conventional and the UI ignores it.
* One user with three tabs is one key with three metas.

The wire events are `Phoenix.Presence`'s own, so if you use `Presence.track/3` and
`Presence.list/1` you get them for free.

## Design questions

### 1. Why can't you track inside `join/3`?

Try it. `Presence.track(socket, ...)` inside `join/3` will not work the way you
expect, and the reason is the point of the exercise: what is the state of the
channel process at the moment `join/3` runs, and has anything been told that it
exists yet? What does the standard `send(self(), :after_join)` pattern buy you, and
what does it cost — specifically, is there a window in which the client is joined
but not present, and can the client observe it?

### 2. Where does presence actually live?

**`Phoenix.Presence` alone.** Everything above works out of the box, including the
cross-node merge you will watch in Track 4. But presence is then only queryable
per topic, from a process, and there is no hook for "when the third person joins,
do X".

**Your `ChannelRuntime` process.** The runtime already has to know who is
connected for the typing indicator in Lab 05, and its state is a plain map you can
shape however you like. But now *you* own the cleanup: when a socket dies, what
removes it from the runtime's state? A link would take the runtime down with the
socket. A monitor means one monitor per connection and a `:DOWN` handler. And a
runtime process that restarts loses everything it knew — is that acceptable for
presence? For anything else in its state?

**Both.** Presence for the wire protocol and cross-node merge, the runtime for
channel-local logic, with the runtime learning about connections some other way.
Now they can disagree. What reconciles them?

Note the interaction with Lab 01: your `ChannelRuntime` tracks `connected_users`
already, and Lab 01's tests require a user to disappear from it on disconnect.
So you have already made a version of this decision once. Is the mechanism you
chose there the same one you would choose here, and if the answer is "presence
duplicates what the runtime knows", which one is redundant?

### 3. What belongs in the metas?

The metas are replicated to every node and pushed to every client on the topic.
That makes them a broadcast channel with a size cost. A name is necessary. What
about the user's email, their avatar url, the last time they typed, their current
draft? Where is the line, and what is the argument for it?

### 4. Presence versus "last seen"

A user who is offline has no presence entry, so "offline for two minutes" and
"offline for two weeks" are the same absence. If you wanted to show "last seen
20 minutes ago", where would that live, and why is it a different kind of data
from what Presence holds? You do not have to build it. You do have to be able to
say why it does not belong here.

## Failure questions

1. A socket process is killed with `Process.exit(pid, :kill)`. How long until the
   user disappears from `Presence.list/1`, and what mechanism does it?
2. The `BeamSlackWeb.Presence` process itself crashes. What happens to every
   tracked presence? Try it in `iex -S mix phx.server`, with two browser tabs open,
   and watch the UI. Does it recover, and if so, what recovers it — OTP, Phoenix,
   or the client?
3. A user has a tab open and their network drops without closing the socket. How
   long do they appear present, and what decides that duration?
4. Two nodes each have the same user present, then the network between them
   partitions and heals. What does `Presence.list/1` return during and after?
   (Track 4 tests this; predict it now and check your prediction later.)
5. Your `ChannelRuntime` for a channel crashes and restarts. Does presence for that
   channel survive? Should it? Does your answer change what state belongs where?

## Acceptance criteria

* `mix test.labs` passes for `test/beamslack_web/channels/channel_presence_test.exs`.
* Two browser tabs as the same user show one entry with a device count of 2. Two
  tabs as different users show two entries. Closing a tab updates both.
* Killing a socket process from `iex` removes the user from the sidebar with no
  cleanup code of yours running.
* A written answer to question 5, since it decides Lab 05's design.

## Non-goals

* No "away" or "do not disturb" status, no idle detection.
* No last-seen persistence.
* No workspace-wide presence yet, even though the sidebar has an obvious place for
  it. Decide the topic taxonomy question in Lab 03 first.

## Hints

* `Presence.track(socket, key, meta)` uses the socket's topic and the channel
  process as the tracked pid. `Presence.track(pid, topic, key, meta)` lets you
  track something else, which is what you would need if the runtime owned this.
* `Phoenix.Presence`'s `fetch/2` callback lets you enrich every presence in a list
  with data from your own store, once per list rather than once per meta. Consider
  whether the name belongs in the metas or in `fetch/2`, and what the difference
  costs when there are 200 people in a channel.
* `assert_push` sees what the joining connection receives. `Endpoint.subscribe/1`
  plus `assert_receive %Phoenix.Socket.Broadcast{}` sees what everyone else
  receives. The tests use both, and the distinction matters for `presence_diff`.
