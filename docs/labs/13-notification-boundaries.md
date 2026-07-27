# Lab 13 — Notification Failure Boundaries

Track 5. Concepts: side effects after a successful write, `Task` vs supervised
`Task` vs Oban, at-least-once delivery, what "the message was sent" means to a
user.

## The problem

Sending a message in BeamSlack does more than insert a row. Mentions create
notifications. Thread replies notify participants. Each of those notifications
is then broadcast on `"user:<id>"`. Tomorrow you might also send email.

The durable write succeeded. The user pressed enter and got a 201. Then the
notification path fails — PubSub is restarting, the mail provider is down, the
node is about to die. **Does the message send fail too?**

If yes, you have coupled a must-succeed operation to a nice-to-have one, and a
transient outage of a secondary system takes down your core product. If no, you
have silently dropped a notification the user expected, and nobody knows.

That trade-off is this lab. There is no single correct answer. There is a correct
*classification* for each path.

## What already exists

* `BeamSlack.Notifications.notify_mention/2` and `notify_thread_reply/2` insert a
  durable row (idempotent via unique index) and then call
  `BeamSlack.Events.notification_created/1`.
* `BeamSlack.Events` broadcasts synchronously, in the calling process, after the
  request has already succeeded at the thing the user asked for. The moduledoc
  says this is the simplest choice and almost certainly the wrong long-term one.
* In-app notifications work end to end. There is no email yet. Inventing a fake
  email provider is encouraged for the exercise.

The product surface is finished. This lab is about *where* the side effects run
and *what happens when they fail*.

## Design questions

### 1. What is in the critical path?

For each of these, decide whether failure of the notification should fail the
message send:

| Side effect | Fail the send? | Why |
| --- | --- | --- |
| Persist the mention row | | |
| Persist the notification row | | |
| Broadcast on `"user:<id>"` | | |
| Send an email | | |
| Index the message for search (hypothetical) | | |

### 2. Three ways to run the work

**Inline (what you have now).** The request process does the work. Latency adds
up. A raise takes down the request — or, if you rescue it, you have swallowed an
error with no retry.

**`Task.start/1` or `Task.async/1` without a supervisor.** Fire and forget, or
await. An unsupervised Task that crashes is gone. `async` without `await` is a
leak. Linking means the request dies with the Task.

**`Task.Supervisor.async_nolink/2`.** The Task is supervised. The request is not
linked. Crashes are logged and restarted according to the supervisor, but there is
still no durability — a node restart loses in-flight Tasks.

**Oban (or any durable job queue).** The work is a database row. A node death
does not lose it. Retries are explicit. You have introduced a second durable
system that must be operated, and at-least-once delivery means your handlers must
be idempotent — which the notification unique index already buys you.

Classify each side effect from the table into one of these four. Be able to say
what happens if the BEAM node dies halfway through.

### 3. Idempotency

The unique index on `{user_id, message_id, kind}` makes creating a notification
safe to retry. Is the *broadcast* safe to retry? Is an email? What would you need
to add before you could put email in Oban?

### 4. Observability

If a notification is dropped, how would you know? Telemetry? A dead-letter table?
A metric on `Events.notification_created` failures? Pick something concrete.

## Failure questions

1. The insert of the message commits. Then `Events.notification_created/1` raises.
   What does the client see today? What should it see?
2. You move the broadcast into an unsupervised `Task`. The node dies before the
   Task runs. Who is missing a notification, and how do they ever get it?
3. You move email into Oban with three retries. The provider is down for an hour.
   What does the user experience, and when?
4. Two nodes both process the same Oban job (at-least-once). What prevents two
   emails? What prevents two in-app notification rows?
5. A user is mentioned in a message, then the message is deleted (hypothetical).
   Should the notification remain? Who owns that decision — the notification
   writer or a cascade?

## Acceptance criteria

* A short written design (a section in this file, or
  `docs/notification-boundaries.md`) answering questions 1 and 2 with a table.
* You have changed *one* side effect's execution strategy from the current inline
  path, with a comment at the call site explaining why that one and not the
  others.
* `mix test` still passes. Mentions and thread replies still create durable
  notification rows.
* You can explain, without looking it up, the difference between `Task.async/1`,
  `Task.Supervisor.async_nolink/2`, and an Oban job when the node is killed.

## Non-goals

* Do not add Oban as a dependency unless you want to for learning — classifying
  the path is enough; implementing the queue is optional.
* Do not build a real email provider. A module that raises or sleeps is fine.
* Do not change the public API of `Messaging.send_message/1`. The failure boundary
  is behind it, not in the controllers.

## Hints

* `Task.Supervisor` is not in the tree yet. Adding one under `BeamSlack.Supervisor`
  is a few lines and is a reasonable part of this lab.
* Rescuing around `Events.notification_created/1` and logging is the smallest
  change that stops a broadcast failure from looking like a send failure. It is
  also how silent data loss starts. Notice both.
* The unique index is doing more work for you than it appears. Name it in your
  write-up when you discuss retries.
