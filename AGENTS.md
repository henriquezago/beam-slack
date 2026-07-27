# BeamSlack collaboration guidance

Before planning or implementing work, read [`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md).
It is the source of truth for the project's learning goals, roadmap, state model,
and division of work between the learner and Codex.

BeamSlack optimizes for learning Elixir, OTP, Phoenix, and the BEAM rather than
shipping quickly. The work is split into five tracks, each pairing an autonomous
Codex build batch with a small number of learner-owned labs.

## Codex builds autonomously

Build the product surface, plumbing, and test harnesses in large batches without
stopping to ask: scaffolding, UI, REST and GraphQL boilerplate, Ecto schemas and
migrations, auth, socket and PubSub plumbing, seeds, fixtures, repetitive tests,
observability, fault-injection tooling, and multi-node dev scripts.

## The learner owns the labs

Process design, GenServer state ownership, supervision topology and restart
strategies, Registry discovery and its races, process lifecycle, monitors and
links, ETS ownership, PubSub topic architecture, Presence architecture,
timer-driven state machines, failure boundaries, backpressure, and distributed
node behavior.

For each lab, deliver two artifacts up front instead of a Socratic dialogue:

1. A design brief at `docs/labs/NN-name.md` stating the problem, constraints,
   options with tradeoffs, failure questions, and acceptance criteria. It poses
   the questions; it does not contain the answer or implementation code.
2. Failing tests as the specification, plus the target module's `@moduledoc` and
   `@spec`s and nothing else. `mix test` is the definition of done.

Never write the body of a function assigned to a lab. Never silently replace,
refactor, or clean up the learner's implementation — if it looks wrong, say so and
ask. Only provide a complete solution when the learner explicitly asks for one.
If a build batch needs a lab module that does not exist yet, stub the call site
and move on.

## Local environment notes

* PostgreSQL runs on `localhost:5432` via Docker Desktop on the Windows host, not
  via `docker` inside WSL. Do not expect the `docker` CLI to be available.
* The frontend uses Yarn.

More deeply nested `AGENTS.md` instructions also apply within their directories.
