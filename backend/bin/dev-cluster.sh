#!/usr/bin/env bash
#
# Starts two BeamSlack nodes and connects them, for Track 4.
#
#   bin/dev-cluster.sh
#
# Node a is on 4000, node b on 4001, both against the same database. Logs are
# interleaved and prefixed. Ctrl-C stops both.
#
# Point one browser at each:
#
#   VITE_API_URL=http://localhost:4000 npm run dev -- --port 5173
#   VITE_API_URL=http://localhost:4001 npm run dev -- --port 5174
#
# Then log in as different users in each, open the same channel, and start asking
# why it works. Presence merges because Phoenix.Presence replicates a CRDT over
# PubSub. Messages arrive because PubSub's PG adapter forwards broadcasts to the
# other node. Nothing else you have written does anything of the kind.
#
set -euo pipefail

cd "$(dirname "$0")/.."

COOKIE="${BEAMSLACK_COOKIE:-beamslack}"
HOST="$(hostname -s)"

cleanup() {
  echo
  echo "stopping cluster..."
  kill 0
}
trap cleanup EXIT INT TERM

start_node() {
  local node="$1" port="$2" color="$3"
  PORT="$port" elixir --sname "beamslack_${node}" --cookie "$COOKIE" -S mix phx.server 2>&1 \
    | sed -u "s/^/$(printf '\033[%sm[%s]\033[0m ' "$color" "$node")/" &
}

start_node a 4000 36
sleep 6
start_node b 4001 35

sleep 8

echo
echo "connecting beamslack_b@${HOST} <- beamslack_a@${HOST}"

# Connect from a throwaway node rather than from inside either server, so the
# handshake is visible and failures are attributable.
elixir --sname beamslack_link --cookie "$COOKIE" -e "
  a = :\"beamslack_a@${HOST}\"
  b = :\"beamslack_b@${HOST}\"

  case Node.connect(a) do
    true -> :ok
    _ -> IO.puts(:stderr, \"could not reach #{inspect(a)}\"); System.halt(1)
  end

  IO.inspect(:erpc.call(a, Node, :connect, [b]), label: \"a -> b\")
  IO.inspect(:erpc.call(a, Node, :list, []), label: \"a sees\")
  IO.inspect(:erpc.call(b, Node, :list, []), label: \"b sees\")
" || echo "cluster link failed; the nodes are still up, connect them by hand"

echo
echo "both nodes running. Ctrl-C to stop."
wait
