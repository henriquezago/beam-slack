# BeamSlack Labs

A lab is a piece of the system the learner designs and implements. Codex writes
the brief and the tests; the learner writes the code.

See "How We Work" in [`../PROJECT_PLAN.md`](../PROJECT_PLAN.md) for the full
protocol. In short:

* The brief states the problem, the constraints, the options and their tradeoffs,
  the failure questions, and the acceptance criteria. It never contains the
  answer or implementation code.
* The tests are the specification. Codex writes the test file plus the target
  module's `@moduledoc` and `@spec`s. `mix test` is the definition of done.
* Codex does not write the body of anything in a lab, and does not rewrite the
  learner's implementation afterwards.

## Index

| Lab | Track | Topic | Status |
| --- | --- | --- | --- |
| [01](01-channel-runtime.md) | 1 | Channel runtime discovery and lifecycle | Ready |
| [02](02-persist-vs-broadcast.md) | 2 | Persist vs broadcast ordering | Ready |
| [03](03-pubsub-architecture.md) | 2 | PubSub topic architecture | Ready |
| [04](04-presence-architecture.md) | 2 | Presence architecture | Ready |
| [05](05-typing-indicators.md) | 2 | Typing indicators as a timer state machine | Ready |
| [06](06-monitors-and-links.md) | 3 | Monitors, links, and who dies with whom | Ready |
| [07](07-ets-ownership.md) | 3 | ETS ownership and the heir | Ready |
| [08](08-backpressure.md) | 3 | Backpressure | Ready |
| [09](09-failure-matrix.md) | 3 | The failure matrix (no code) | Ready |
| [10](10-cross-node-discovery.md) | 4 | Finding a process on another node | Ready |
| [11](11-kill-a-node.md) | 4 | Kill a node and attribute the recovery | Ready |
| [12](12-network-partitions.md) | 4 | Partitions, and why there is no right answer | Ready |
| [13](13-notification-boundaries.md) | 5 | Notification failure boundaries | Ready |

## Brief template

```markdown
# Lab NN — Title

Track N. Concepts: ...

## The problem

## What already exists

## The API contract

## Design questions
### 1. ...
Options, with the tradeoff each one buys.

## Failure questions

## Acceptance criteria

## Non-goals

## Hints
```
