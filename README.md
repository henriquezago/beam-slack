# BeamSlack

BeamSlack is a learning project for exploring Elixir, Phoenix, OTP, and the BEAM by
building a Slack-like application. It optimizes for understanding the runtime rather
than for shipping quickly.

Two documents are the source of truth:

- [`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md) — the five tracks, what Codex builds
  and what the learner owns, and the collaboration rules.
- [`docs/labs/`](docs/labs/) — the design briefs for the parts the learner implements.
  Each one pairs with a failing test suite that defines "done".

## Requirements

- Elixir 1.17+ and Erlang/OTP 25+
- Node.js 20.19+ (Node.js 24 LTS is recommended)
- Yarn Classic 1.22.22 (pinned via [Volta](https://volta.sh/) in `frontend/package.json`)
- Docker Desktop (or another Docker Engine with Compose) for PostgreSQL 17

## Running it

Start PostgreSQL:

```bash
docker compose up -d postgres
```

The named Docker volume `postgres_data` holds the database files; no host
PostgreSQL installation is needed.

Set up and start the backend:

```bash
cd backend
mix setup          # deps, create, migrate, seed
mix phx.server
```

In another terminal, the frontend:

```bash
cd frontend
yarn install
yarn dev
```

Open <http://localhost:5173>. Vite proxies `/api` and `/socket` to Phoenix on port
4000.

Seeded accounts, all with password `password123`:

```
henrique@example.com   alice@example.com   bob@example.com   carol@example.com
```

### Running with a node name

`mix phx.server` starts an unnamed node, which is fine until you want to reach it
from a mix task or run two of them. `bin/dev-node.sh` starts a named one instead,
and everything in `bin/` and the `beamslack.*` tasks assumes it:

```bash
cd backend
bin/dev-node.sh a          # beamslack_a, port 4000
bin/dev-node.sh b          # beamslack_b, port 4001
```

Point a browser session at each:

```bash
cd frontend
yarn dev:a                 # localhost:5173 -> node a
yarn dev:b                 # localhost:5174 -> node b
```

The health badge in the sidebar shows which node the session is talking to.

## Observability and fault injection

Dev only. All of it is compiled out of other environments.

| | |
| --- | --- |
| <http://localhost:4000/dev/dashboard> | LiveDashboard: processes, ETS, metrics |
| <http://localhost:4000/dev/faults> | fault-injection endpoints and a snapshot |
| `mix beamslack.kill --list` | what can be killed, and whether it is alive |
| `mix beamslack.kill presence` | kill a named process and see what came back |
| `mix beamslack.flood --count 50000 --watch` | flood a process past its drain rate |
| `mix beamslack.loadtest --clients 50 --rate 1` | open N real WebSocket clients |
| `mix beamslack.cluster` | node status, `connect`, `check`, `partition`, `heal` |

Supervisor reports are enabled in `config/dev.exs`, which Elixir filters out by
default. Without them a supervision tree can collapse with nothing in the log but
the first crash. See the comment there.

## Tests

```bash
cd backend
mix test           # the suite that must always be green
mix test.labs      # the lab specs, which fail until you implement them

cd ../frontend
yarn test
yarn build
```

Backend tests need PostgreSQL. `mix test` excludes anything tagged `:lab`, so a
failing lab never blocks the main suite.

## Where state lives

- **PostgreSQL** — users, workspaces, channels, messages, reactions, mentions,
  notifications. Everything that must survive a crash.
- **Process state** — channel runtimes, typing timers. Meaningless after a restart,
  which is why it is allowed to be lost.
- **ETS** — the rate limiter. Shared, mutable, and owned by a process that can die.
- **Phoenix.Presence** — who is connected, replicated across nodes as a CRDT and
  derived entirely from which socket processes are alive.

Being able to say which of those a given fact belongs in is most of what this
project is for.
