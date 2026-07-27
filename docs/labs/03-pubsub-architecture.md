# Lab 03 — PubSub Topics and Who Subscribes

Track 2. Concepts: `Phoenix.PubSub` as a process registry, topic design as an
authorization boundary, fan-out cost, who owns a subscription.

## The problem

`Phoenix.PubSub` is a name-to-pids table with a broadcast operation. That is all
it is. It does not know what a channel is, it does not check permissions, and it
delivers to whoever subscribed. Every property you want out of it — that private
channel traffic stays private, that a message reaches all seven of a user's tabs,
that a fan-out to 5,000 subscribers does not stall a caller — is a consequence of
how you name topics and which processes subscribe to them.

Lab 02 got a message from one client to another. This lab is about whether that
still works when there are many channels, many workspaces, private channels, and
eventually a second node.

## What already exists

`Phoenix.PubSub` runs under `BeamSlack.Supervisor` as `BeamSlack.PubSub`, and
`BeamSlackWeb.Endpoint` is configured with `pubsub_server: BeamSlack.PubSub`, so
`Endpoint.broadcast/3` and `Endpoint.subscribe/1` work.

`ChannelChannel.join/3` subscribes implicitly: joining topic `"channel:<id>"` makes
the socket process a subscriber of that topic. You get that for free, and it is
worth understanding that you got it, because it is the thing you might replace.

The React `useChannelRealtime` hook joins one topic per open channel and leaves on
unmount.

## The contract

Message traffic for channel `<id>` travels on `"channel:<id>"`, with the payload
shape from Lab 02. `channel_broadcast_test.exs` also asserts what must *not*
happen: no leakage onto a sibling channel's topic, and no message bodies on a
workspace-wide topic.

Everything else about the taxonomy is yours to design.

## Design questions

### 1. What topics exist?

You have at least these facts to notify people about: a new message, a channel
being created, a user joining a workspace, presence changes, typing. Sketch the
topic namespace before writing code. Candidates:

* `"channel:<id>"` — message traffic. Already in use.
* `"workspace:<id>"` — channel-created and member-joined events. But note the test:
  if this topic carries message bodies, every workspace member receives traffic
  from private channels they cannot read. PubSub has no authorization; the topic
  *is* the authorization boundary.
* `"user:<id>"` — a per-user fan-in topic. Mentions and notifications in Track 5
  need something like this. Who subscribes, the socket or something longer-lived?
* Presence topics. `Phoenix.Presence` piggybacks on the channel topic by default.
  Lab 04 asks whether that is what you want.

For each topic, answer: who publishes, who subscribes, and what is the worst thing
a subscriber could learn that it should not know?

### 2. Which process subscribes?

Right now the socket process subscribes, because `join/3` does it. The alternative
is that `ChannelRuntime` (your Lab 01 process) subscribes and pushes to sockets it
knows about.

**Socket subscribes.** Fan-out is PubSub's problem, it is already written, and it
works across nodes. But every socket is an independent subscriber, so a message in
a channel with 5,000 connections means 5,000 sends, and nothing in the system has
a single view of "who is in this channel" other than the PubSub table itself.

**`ChannelRuntime` subscribes and relays.** Now one process per channel owns the
channel's state, which is a natural place for typing timers, rate limits, and a
recent-message cache. But it is also a single process every message must pass
through: a bottleneck and a single point of failure, and a mailbox that can grow
faster than it drains. Track 3 makes you feel that one directly.

**Both.** The runtime subscribes for its own bookkeeping while sockets subscribe
for delivery. Two subscribers means the message is delivered twice; is that a
problem or is it exactly what you want?

Concretely: if you want a "recent messages" cache so a joining client does not hit
PostgreSQL, which of these designs can even have one?

### 3. Fan-out and back pressure

`Phoenix.PubSub.broadcast/3` in the default `PG2`/`PG` adapter sends to local
subscribers from the calling process. Read that again: the caller does the sends.

* Who pays the cost of a broadcast to 5,000 subscribers, and what is that process
  not doing while it pays?
* What happens to the sender's reply latency?
* `broadcast/3` versus `local_broadcast/3` — when is the difference invisible, and
  when does it become the whole story? (Track 4 answers the second half.)
* If a subscriber is slow, does the broadcaster block? Where does the backlog
  accumulate?

### 4. What happens on reconnect?

A client drops and rejoins. Its subscription is gone and re-established, but the
messages sent in between were delivered to a process that no longer exists. Where
does the client get them? Notice that this is a durability question that PubSub
cannot answer, and that it constrains Lab 02's ordering choice.

## Failure questions

1. A subscriber process dies. Does PubSub know? What removes it from the table, and
   is that mechanism a link, a monitor, or something else? (Read the source if you
   are not sure. It is short.)
2. A broadcaster dies mid-broadcast. Do some subscribers get the message and others
   not? Is there any way to make that atomic, and do you want it to be?
3. You broadcast to a topic nobody subscribes to. What happens, and is that an
   error?
4. A user is removed from a private channel but their socket is still joined. Do
   they keep receiving messages? What stops it, and is that in PubSub, the channel,
   or the context module?
5. Two processes subscribe with the same topic from the same process. How many
   copies of each message arrive?

## Acceptance criteria

* `mix test.labs` passes for `test/beamslack_web/channels/channel_broadcast_test.exs`.
* A written topic table: topic pattern, publisher, subscriber, payload, and the
  authorization argument for why that payload on that topic is safe.
* Three browser tabs: two on `#general`, one on `#random`. Messages appear in the
  right places and nowhere else.
* Your answer to question 1 above, with the mechanism named.

## Non-goals

* No custom PubSub adapter, and do not swap out the PG adapter.
* No cross-node work. Track 4 is where `local_broadcast/3` starts to matter.
* No rate limiting yet; that is Track 3's ETS lab.

## Hints

* `Phoenix.PubSub.subscribers/2` does not exist, but the registry behind PubSub is
  inspectable if you go looking. Doing so is a good way to answer question 5.
* A `Phoenix.Socket.Broadcast` struct is what a subscribed *non-channel* process
  receives, while a joined channel gets an internal message that `handle_info/2`
  or `Phoenix.Channel`'s default handling turns into a push. The broadcast test
  relies on both behaviors, which is why it asserts with two different macros.
* `intercept/1` in a channel lets you transform a broadcast per-socket before it is
  pushed. It also means the fan-out cost moves into each socket process. It is the
  right tool for exactly one thing in this project; see if you can spot it.
