#!/usr/bin/env bash
#
# Starts one named BeamSlack node.
#
#   bin/dev-node.sh              # node a, port 4000
#   bin/dev-node.sh b            # node b, port 4001
#   bin/dev-node.sh c 4002       # explicit port
#
# A node needs three things to be reachable: a name, a cookie, and a port nobody
# else is on. Two nodes on one machine share a database on purpose. The point of
# Track 4 is that they do *not* share process state, and that everything which
# looks like it works across nodes -- PubSub, Presence -- works because something
# explicitly replicates it, while everything else (a Registry, a GenServer name,
# an ETS table) is stubbornly local.
#
# Once two are up, connect them from either IEx session:
#
#   Node.connect(:"beamslack_b@$(hostname -s)")
#   Node.list()
#
set -euo pipefail

cd "$(dirname "$0")/.."

NODE="${1:-a}"
SNAME="beamslack_${NODE}"

case "$NODE" in
  a) DEFAULT_PORT=4000 ;;
  b) DEFAULT_PORT=4001 ;;
  c) DEFAULT_PORT=4002 ;;
  *) DEFAULT_PORT=4003 ;;
esac

PORT="${2:-$DEFAULT_PORT}"
COOKIE="${BEAMSLACK_COOKIE:-beamslack}"

echo "node   ${SNAME}@$(hostname -s)"
echo "port   ${PORT}"
echo "cookie ${COOKIE}"
echo
echo "dashboard  http://localhost:${PORT}/dev/dashboard"
echo "frontend   VITE_API_URL=http://localhost:${PORT} npm run dev"
echo

PORT="$PORT" exec elixir \
  --sname "$SNAME" \
  --cookie "$COOKIE" \
  -S mix phx.server
