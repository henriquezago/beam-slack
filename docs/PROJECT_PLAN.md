# Project: BeamSlack — Learn Elixir, OTP, and the BEAM by Building a Slack-Like Application

## Goal

Build a Slack-like collaboration platform using:

* Elixir
* Phoenix
* Ecto
* PostgreSQL
* React
* TypeScript

The primary objective is not simply to build a working product.

The primary objective is to deeply understand the Erlang/Elixir ecosystem and the concepts that make the BEAM unique:

* lightweight processes
* message passing
* process isolation
* GenServer
* Supervisor
* DynamicSupervisor
* Registry
* process links
* process monitors
* supervision trees
* restart strategies
* "let it crash"
* ephemeral vs durable state
* Phoenix Channels
* Phoenix PubSub
* Phoenix Presence
* ETS
* background jobs
* distributed Erlang nodes
* fault tolerance
* failure recovery

I have previous professional experience with Elixir, but I did not have enough opportunities to deeply explore OTP and BEAM architecture.

This project should prioritize those concepts.

---

# AI Collaboration Rules

You are my pair programmer and tutor.

Do not optimize for implementing the application as quickly as possible.

Optimize for maximizing my understanding of Elixir, OTP, Phoenix, and the BEAM.

There are two categories of tasks.

---

# Tasks Codex May Implement Directly

You may directly generate:

* Phoenix project scaffolding
* React project scaffolding
* TypeScript configuration
* CSS
* visual components
* forms
* standard CRUD
* repetitive Ecto schemas
* Ecto migrations
* authentication boilerplate
* GraphQL boilerplate
* basic Phoenix controllers
* repetitive tests
* Docker development configuration
* PostgreSQL setup
* utility functions
* frontend state handling
* UI components
* API client code

The purpose is to avoid spending learning time on repetitive code.

---

# Core Learning Tasks

DO NOT immediately implement the following for me:

* raw Elixir processes
* message passing
* GenServer
* Supervisor
* DynamicSupervisor
* Registry
* process monitoring
* process linking
* supervision-tree design
* restart strategies
* process lifecycle
* ETS ownership
* PubSub architecture decisions
* Presence architecture
* fault recovery
* state ownership
* distributed node behavior
* distributed process discovery

For these tasks:

1. Explain the problem.
2. Ask me how I would solve it.
3. Evaluate my proposal.
4. Challenge incorrect assumptions.
5. Explain tradeoffs.
6. Give hints.
7. Let me implement the solution.
8. Review my implementation.
9. Only provide a complete solution if I explicitly ask.

Never silently replace my implementation.

---

# Project Concept

The application is called:

**BeamSlack**

It is a simplified Slack-like collaboration application.

Users belong to workspaces.

A workspace contains channels.

Users can:

* join workspaces
* join channels
* send messages
* reply in threads
* see online users
* see typing indicators
* react to messages
* receive notifications
* search message history

Later versions may support:

* private channels
* direct messages
* file uploads
* message editing
* message deletion
* mentions
* background notifications
* multiple connected devices
* GraphQL
* distributed BEAM nodes

The architecture should evolve gradually.

Do not introduce unnecessary infrastructure early.

Avoid Redis, Kafka, RabbitMQ, Kubernetes, or microservices unless a later problem clearly justifies them.

Prefer learning what OTP and the BEAM provide first.

---

# State Classification

Whenever implementing a feature, explicitly classify its state.

## Durable State

State that must survive process, application, and node crashes.

Examples:

* users
* workspaces
* channels
* workspace memberships
* channel memberships
* messages
* threads
* reactions
* file metadata
* notification history

Normally stored in PostgreSQL or durable object storage.

---

## Ephemeral State

State that may disappear and be reconstructed.

Examples:

* online presence
* active socket connections
* typing indicators
* temporary process state
* caches

Potential technologies:

* Elixir process state
* Phoenix Presence
* ETS

---

## Recoverable Operational State

An operation that should survive worker failure.

Examples:

* image processing
* email notification
* push notification
* file processing
* search indexing

Potential technologies:

* Oban
* persisted job state
* retries
* idempotency

Always discuss which category a new feature belongs to.

---

# Phase 0 — Project Setup

Codex may implement this phase.

Create:

Backend:

* Phoenix
* Ecto
* PostgreSQL

Frontend:

* React
* TypeScript

Configure:

* local development
* database
* backend tests
* frontend tests

Create a simple health endpoint.

Do not implement custom OTP processes yet.

---

# Phase 1 — Slack Domain Model

Create the durable relational model.

Entities:

## User

* id
* name
* email

## Workspace

* id
* name
* owner_id

## WorkspaceMember

* workspace_id
* user_id
* role

Possible roles:

* owner
* admin
* member

## Channel

* id
* workspace_id
* name
* type

Initially support:

* public
* private

## ChannelMember

For private channels and membership tracking.

## Message

* id
* channel_id
* sender_id
* body
* inserted_at

Codex may generate:

* migrations
* schemas
* changesets
* repetitive context functions

Before implementation, explain and review the relationships with me.

Initial features:

* create user
* create workspace
* join workspace
* create channel
* join channel
* send message
* list messages

Everything should initially work synchronously.

No real-time behavior yet.

---

# Learning Checkpoint 1

Ask me:

1. Which data is durable?
2. Where does the data survive an application restart?
3. What happens if Phoenix crashes after a message has been committed?
4. What happens if Phoenix crashes before the transaction commits?

Discuss transaction boundaries.

---

# Phase 2 — Raw Elixir Processes

Before GenServer, create a learning experiment.

Do not implement this for me.

Create one raw Elixir process representing temporary runtime state for a channel.

Example state:

* channel_id
* connected users
* number of active connections

Use:

* `spawn`
* `send`
* `receive`

I should manually implement a recursive receive loop.

Exercises:

1. Spawn the process.
2. Send events.
3. Update immutable state.
4. Query the state.
5. Inspect its PID.
6. Kill the process.
7. Observe the state disappearing.

Teach:

* PID
* mailbox
* process isolation
* immutable state
* recursive receive loops

Ask:

> Why did killing this process not delete the channel messages?

The answer should reinforce:

Runtime process state and durable database state are different things.

---

# Phase 3 — GenServer

Convert the raw process into a GenServer.

Do not provide the implementation immediately.

I should implement:

* `start_link`
* `init`
* `handle_call`
* `handle_cast`
* `handle_info`

Teach:

* `call`
* `cast`
* ordinary mailbox messages

Possible runtime state:

* channel ID
* current active-user count
* temporary statistics

Do not store permanent Slack message history only in the GenServer.

Discuss:

> Should every channel have a GenServer?

Do not assume the answer is yes.

Consider:

* inactive channels
* millions of channels
* process lifecycle
* state ownership

---

# Phase 4 — Supervisors

Run the Channel process without supervision.

Kill it.

Observe that it stays dead.

Then introduce Supervisor.

Do not implement it for me.

Teach:

* child specifications
* restart policies
* supervision trees

Discuss:

* permanent
* transient
* temporary

Discuss strategies:

* one_for_one
* one_for_all
* rest_for_one

Let me choose and justify the strategy.

Then test:

ChannelProcess PID A

→ crash

→ ChannelProcess PID B

The process returns.

Its previous in-memory state does not.

Core lesson:

**Supervisors restore processes, not memory.**

---

# Phase 5 — DynamicSupervisor

Channels may have dynamically created runtime processes.

Introduce DynamicSupervisor.

Do not implement directly.

Potential conceptual architecture:

DynamicSupervisor

* ChannelRuntime #general
* ChannelRuntime #engineering
* ChannelRuntime #random

Discuss when a runtime process should exist.

Questions:

* Should every database channel have one?
* Should it only start when someone connects?
* Should it shut down when nobody is connected?
* Who decides when it stops?

Let me design the lifecycle.

---

# Phase 6 — Registry

Introduce process discovery.

Avoid forcing callers to store PIDs.

Desired conceptual API:

`ChannelRuntime.get_or_start(channel_id)`

Teach Registry.

I should implement:

* process registration
* lookup
* dynamic startup

Discuss concurrent startup.

Example:

Request A asks for channel 10.

Request B asks for channel 10.

Both arrive simultaneously.

Both see no process.

What prevents duplicate channel processes?

Let me reason about race conditions.

---

# Learning Checkpoint 2 — Supervision Tree

Ask me to explain the application tree.

Conceptually:

Application Supervisor

* Repo
* Phoenix Endpoint
* Registry
* ChannelDynamicSupervisor

  * ChannelRuntime A
  * ChannelRuntime B
  * ChannelRuntime C

Ask:

1. What happens when one channel process crashes?
2. What happens if DynamicSupervisor crashes?
3. What happens if Registry crashes?
4. What happens if the entire BEAM node crashes?
5. Which state survives each failure?

Do not continue until I can explain this confidently.

---

# Phase 7 — Phoenix Channels

Add real-time Slack messaging.

Connect React using Phoenix Channels.

Codex may scaffold:

* socket connection
* basic Channel module
* frontend socket client

But discuss message flow before implementation.

Desired flow:

React

→ Phoenix Channel

→ Messaging Context

→ PostgreSQL

→ broadcast

→ connected clients

Ask:

Should we:

A. broadcast before persistence

or

B. persist before broadcasting?

Analyze:

* database failure
* process crash
* duplicate sends
* client reconnect

Messages should normally be persisted before being considered successfully sent.

---

# Phase 8 — Phoenix PubSub

Introduce PubSub.

Teach the distinction between:

* direct process messages
* GenServer calls
* Phoenix Channels
* Phoenix PubSub

Example:

Message created

→ Messaging domain emits event

→ PubSub

→ multiple subscribers

Potential subscribers:

* channel WebSocket
* notification service
* analytics
* audit logger

Discuss loose coupling.

Do not introduce unnecessary abstraction.

---

# Phase 9 — Phoenix Presence

Implement workspace and channel presence.

Use Phoenix Presence.

Examples:

Workspace:

* Henrique online
* Alice online
* Bob offline

A user may have:

* desktop connection
* browser connection
* mobile connection

Teach:

One user may have multiple presences.

Exercises:

1. Open two tabs.
2. User appears online.
3. Close one tab.
4. User remains online.
5. Close second tab.
6. User becomes offline.

Discuss why presence should usually not use PostgreSQL as its primary source of truth.

Compare:

* process state
* ETS
* Presence
* database

---

# Phase 10 — Typing Indicators

Add:

"Henrique is typing..."

This is deliberately ephemeral.

Do not store typing events permanently.

Use:

* Channel events
* PubSub
* timers

I should manually implement timeout behavior.

Example:

typing_started

→ no more events for N seconds

→ typing expired

Use this to teach timers and process messages.

---

# Phase 11 — Threads

Add Slack-style message threads.

Data model:

Message

* optional parent_message_id

or another appropriate relational model.

Codex may implement database boilerplate.

Discuss:

* retrieving thread messages
* broadcasting thread updates
* subscriptions

Thread messages are durable.

Thread viewer presence is ephemeral.

Keep these concerns separate.

---

# Phase 12 — Reactions

Add emoji reactions.

Examples:

👍
❤️
😂

Persist reactions.

Make reactions real-time through PubSub.

Discuss idempotency.

What happens if the same reaction request is sent twice?

Consider uniqueness constraints such as:

user + message + emoji.

---

# Phase 13 — Mentions

Implement:

@henrique

@channel

When sending a message:

1. persist message
2. detect mentions
3. emit notification events

Do not initially send emails.

Use this feature to introduce event-driven architecture.

---

# Phase 14 — Notification Service

Create a notification component.

Examples:

* mention
* thread reply
* direct message

Start with in-app notifications.

Later support email.

Discuss what should be synchronous vs asynchronous.

Example:

Sending a Slack message should not fail because the email provider is unavailable.

Introduce failure boundaries.

---

# Phase 15 — Process Monitoring

Create an explicit learning exercise with:

`Process.monitor/1`

Process A monitors Process B.

Kill B.

Observe `:DOWN`.

Teach:

* monitors
* links

Discuss when you want:

* failure propagation
* failure observation

I should implement this manually.

---

# Phase 16 — ETS

Introduce ETS for an appropriate use case.

Possible examples:

* temporary rate-limit counters
* hot workspace metadata cache
* frequently accessed lookup data

Do not store permanent messages in ETS.

I should manually:

1. create table
2. insert values
3. read from multiple processes
4. kill owner
5. observe behavior

Teach:

* ETS ownership
* public/protected/private
* memory lifetime

Discuss ETS `heir` conceptually.

---

# Phase 17 — Fault Injection Lab

Create development-only mechanisms to deliberately cause failures.

Examples:

* crash channel runtime
* kill random GenServer
* terminate worker
* disconnect PostgreSQL
* disconnect browser
* terminate Phoenix node

For every failure, ask:

1. What died?
2. What survived?
3. What restarted?
4. What data disappeared?
5. What data remained?
6. Who performed recovery?
7. Is the behavior acceptable?

This is one of the most important phases.

---

# Phase 18 — GraphQL with Absinthe

Introduce GraphQL.

Use:

* Absinthe

Queries:

* current user
* workspace
* channels
* channel history
* thread messages

Mutations:

* create channel
* send message
* add reaction

Codex may generate schema boilerplate.

I should understand and review resolvers.

Teach:

* schema
* types
* queries
* mutations
* resolver
* context
* authentication
* authorization

---

# Phase 19 — N+1 Problem

Deliberately implement a query that causes N+1.

Example:

Workspace

→ Channels

→ Messages

→ Authors

Observe generated SQL queries.

Then introduce:

* Dataloader
* batching

Do not solve the problem before demonstrating it.

---

# Phase 20 — GraphQL Subscriptions

Implement one feature using GraphQL Subscriptions.

Compare it against Phoenix Channels.

Questions:

* Which provides better ergonomics?
* Which fits the existing frontend?
* Are we duplicating real-time mechanisms?

Do not blindly replace Phoenix Channels.

---

# Phase 21 — File Uploads

Add Slack-style attachments.

Architecture:

Client

→ request upload

→ backend creates attachment metadata

→ signed URL

→ object storage

→ client confirms completion

Persist states:

* pending
* completed
* failed

Do not route large files through a long-lived GenServer unnecessarily.

Discuss:

* browser crash
* backend crash
* duplicate completion request
* incomplete upload

Introduce idempotency.

---

# Phase 22 — Background Jobs with Oban

Add asynchronous tasks.

Examples:

* generate image thumbnail
* send email notification
* process uploaded file

Use Oban.

Teach differences between:

* `Task`
* supervised `Task`
* durable background job

Ask:

> What happens if the BEAM node crashes halfway through this operation?

Use the answer to determine if persistence is required.

---

# Phase 23 — Search

Implement Slack-style message search.

Start with PostgreSQL search capabilities.

Do not introduce Elasticsearch immediately.

Search:

* workspace messages
* messages by user
* messages in channel

Only introduce dedicated search infrastructure if PostgreSQL limitations become a meaningful learning problem.

---

# Phase 24 — Multiple BEAM Nodes

Run:

Node A

Node B

Connect using distributed Erlang.

Learn:

* `Node.list`
* node connection
* process communication across nodes

Run Phoenix instances on both.

Connect different clients to different nodes.

Observe:

* PubSub
* Presence
* channels

Do not hide the setup behind Kubernetes.

Understand the node topology manually.

---

# Phase 25 — Kill a Node

Connect:

User A → Node A

User B → Node B

Then kill Node A.

Observe:

* User A WebSocket
* Node A processes
* Node B processes
* Presence
* PostgreSQL messages
* reconnection

Ask me:

Which recovery mechanisms came from:

* OTP
* Phoenix
* client reconnect logic
* PostgreSQL
* distributed infrastructure

Do not conflate them.

---

# Phase 26 — Network Partitions

Discuss and simulate where practical:

Node A cannot see Node B.

Explore:

* stale presence
* distributed state
* split brain

Discuss CAP theorem conceptually.

The goal is not to build Raft or distributed consensus.

The goal is to understand that BEAM distribution does not eliminate distributed-systems problems.

---

# Phase 27 — Observability

Add:

* Telemetry
* LiveDashboard
* structured logging

Inspect:

* process count
* memory
* scheduler utilization
* mailbox size

Create an experiment where one process receives messages faster than it processes them.

Observe mailbox growth.

Discuss:

* bottlenecks
* backpressure
* process design

---

# Phase 28 — Load Testing

Simulate Slack clients.

Start with:

100 concurrent connections

Then:

1,000

Increase when reasonable.

Simulate:

* users joining channels
* presence
* messages
* typing events
* reconnects

Observe BEAM behavior.

The purpose is not achieving a specific benchmark.

The purpose is understanding concurrency.

---

# Optional Advanced Features

After the core project:

## Direct Messages

Private 1:1 conversations.

## Group DMs

Small private groups outside normal channels.

## Message Editing

Handle real-time updates.

## Message Deletion

Discuss hard delete vs soft delete.

## Pinned Messages

Durable feature.

## Scheduled Messages

Excellent Oban exercise.

## Reminder System

Example:

`/remind me in 2 hours`

Good exercise for durable scheduled jobs.

## Bot System

Create Slack-like bots.

Bots subscribe to events through PubSub.

## Slash Commands

Examples:

`/giphy`

`/remind`

`/status`

Good opportunity to explore extensibility.

## AI Bot

Create a channel AI assistant.

Use asynchronous LLM requests.

Explore:

* timeout
* cancellation
* streaming
* rate limiting
* background work

## Webhooks

External applications can publish events.

Good exercise for idempotency and authentication.

---

# Final Learning Review

At the end, ask me to explain BeamSlack entirely without assistance.

## Processes

* What is a BEAM process?
* What is its mailbox?
* Why is state immutable?
* What happens when a process crashes?

## OTP

* GenServer
* Supervisor
* DynamicSupervisor
* Registry
* links
* monitors

## Failure

Explain:

* channel process crash
* WebSocket process crash
* background worker crash
* database failure
* complete node crash

## State

Explain which state belongs in:

* PostgreSQL
* process memory
* ETS
* Phoenix Presence
* object storage
* Oban

## Real-time

Explain:

* Phoenix Channels
* PubSub
* Presence

## Distributed Systems

Explain:

* multiple BEAM nodes
* node failure
* client reconnect
* network partitions

---

# Core Principle

Throughout development, repeatedly ask:

> What happens if this process dies right now?

Then:

> What happens if the entire node dies right now?

Then:

> What information do we actually need to recover?

The goal is to stop thinking only in terms of objects and services and start thinking in terms of:

* isolated processes
* state ownership
* message passing
* failure boundaries
* supervision
* recovery

---

# First Codex Task

Inspect the current repository.

If empty:

1. Create the minimal Phoenix + Ecto + PostgreSQL backend.
2. Create the React + TypeScript frontend.
3. Configure local development.
4. Create only a health-check flow.
5. Explain the resulting directory structure.
6. Do not implement custom GenServers.
7. Do not implement custom Supervisors.
8. Do not implement Registry.
9. Do not implement Phoenix Presence.
10. Do not introduce GraphQL yet.

Then stop.

Present Phase 1 as the next task and ask me to reason about the Slack domain model before generating the migrations.
