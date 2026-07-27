defmodule BeamSlackWeb.HealthController do
  use BeamSlackWeb, :controller

  @moduledoc """
  Liveness, plus the identity of the node answering.

  The node name matters from Track 4 onward. With two nodes behind two browser
  tabs, "which one am I talking to" stops being obvious, and every observation
  about cross-node behavior is worthless without it. `connected_nodes` is the
  other half: a node that thinks it is alone will still serve requests perfectly
  while quietly failing to replicate anything.
  """

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    json(conn, %{
      status: "ok",
      node: to_string(Node.self()),
      connected_nodes: Enum.map(Node.list(), &to_string/1)
    })
  end
end
