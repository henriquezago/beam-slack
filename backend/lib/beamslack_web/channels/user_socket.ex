defmodule BeamSlackWeb.UserSocket do
  @moduledoc """
  The WebSocket entry point.

  One socket per browser tab. Authentication happens once here, using the same
  `Phoenix.Token` the JSON API accepts, passed as the `token` connect param
  because browsers cannot set headers on a WebSocket handshake.

  Everything about this connection is ephemeral. When the tab closes, this
  process dies, and with it every channel process it was carrying. Nothing here
  needs to be recovered; the client reconnects and re-derives its view from
  PostgreSQL.
  """

  use Phoenix.Socket

  alias BeamSlackWeb.Auth

  channel "channel:*", BeamSlackWeb.ChannelChannel
  channel "user:*", BeamSlackWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Auth.verify_user(token) do
      {:ok, user} -> {:ok, assign(socket, current_user: user)}
      {:error, _reason} -> :error
    end
  end

  @impl true
  def connect(_params, _socket, _connect_info), do: :error

  @doc """
  Identifies the socket so every connection belonging to one user can be
  disconnected at once, for example after a password change.

  Returning nil instead would make the connection anonymous and unaddressable.
  """
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
