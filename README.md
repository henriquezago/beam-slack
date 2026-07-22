# BeamSlack

BeamSlack is a learning project for exploring Elixir, Phoenix, OTP, and the BEAM by building a Slack-like application. Phase 0 contains only a Phoenix JSON API, Ecto/PostgreSQL configuration, a React/TypeScript frontend, and an end-to-end health check.

The complete learning roadmap and Codex collaboration rules live in
[`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md). Keeping it in the repository gives
new development and Codex sessions the same source of truth.

## Requirements

- Elixir 1.17+ and Erlang/OTP 25+
- Node.js 20.19+ (Node.js 24 LTS is recommended)
- Yarn Classic 1.22.22 (pinned via [Volta](https://volta.sh/) in `frontend/package.json`)
- Docker Desktop (or another Docker Engine with Compose) for PostgreSQL 17

## Local development

Start PostgreSQL in Docker:

```powershell
docker compose up -d postgres
```

BeamSlack does not rely on a PostgreSQL installation or Windows service on the host. The named Docker volume `postgres_data` holds the database files.

Install and start the backend:

```powershell
cd backend
mix setup
mix phx.server
```

In another terminal, install and start the frontend:

```powershell
cd frontend
yarn install
yarn dev
```

Volta reads the Node and Yarn pins from `frontend/package.json` when you work in that directory.

Open http://localhost:5173. Vite proxies `/api` requests to Phoenix at http://127.0.0.1:4000.

The API health endpoint is also available directly at http://127.0.0.1:4000/api/health.

## Tests

```powershell
cd backend
mix test

cd ../frontend
yarn test
yarn build
```

Backend tests require PostgreSQL. The frontend tests mock the health response and do not require Phoenix to be running.

## State in Phase 0

- The health response is stateless.
- PostgreSQL is configured as the future home of durable domain state.
- No custom process state, Registry, Presence, or other ephemeral application state exists yet.
