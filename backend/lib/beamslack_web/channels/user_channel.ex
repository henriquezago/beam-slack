defmodule BeamSlackWeb.UserChannel do
  @moduledoc """
  Per-user fan-in topic: `"user:<user_id>"`.

  Notifications and other private events land here. A user with several tabs gets
  one delivery per connection from a single `Endpoint.broadcast`, which is the
  whole reason the topic is per-user rather than per-socket.
  """

  use BeamSlackWeb, :channel

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if socket.assigns.current_user.id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end
end
