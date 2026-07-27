defmodule BeamSlackWeb.Presence do
  @moduledoc """
  Phoenix Presence for BeamSlack.

  This module is boilerplate; the interesting decisions are Lab 04's. Presence
  keeps its state in a replicated, per-node CRDT held in ETS, which means:

    * it is ephemeral, and correctly so
    * it survives a channel process crash but not a node restart
    * it merges across nodes without a coordinator, which Track 4 exploits

  Nothing here belongs in PostgreSQL. A `users.online` column would be a lie the
  moment a node died without cleaning up after itself.
  """

  use Phoenix.Presence,
    otp_app: :beamslack,
    pubsub_server: BeamSlack.PubSub
end
