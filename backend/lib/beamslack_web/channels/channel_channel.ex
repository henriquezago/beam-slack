defmodule BeamSlackWeb.ChannelChannel do
  @moduledoc """
  The real-time channel for one BeamSlack channel, on topic `"channel:<id>"`.

  `join/3` is plumbing and is finished. The three handlers below are Labs 02, 04,
  and 05, and they raise until you write them. Joining still works, so the app
  keeps functioning over HTTP while the real-time paths are unimplemented.

  ## The wire contract

  The React client is already built against these events, so keep the names and
  payload shapes.

  Client to server:

    * `"new_message"` with `%{"body" => body}`, expecting a reply of
      `{:ok, message}` or `{:error, %{reason: ...}}`
    * `"typing"` with `%{}`

  Server to client:

    * `"new_message"` with a message object shaped like `BeamSlackWeb.MessageJSON.data/1`
    * `"typing_started"` with `%{user_id: id, name: name}`
    * `"typing_stopped"` with `%{user_id: id}`
    * `"presence_state"` and `"presence_diff"`, which `Phoenix.Presence` sends for you

  ## What lives where

  This process is per-connection and per-channel. Two browser tabs viewing
  `#general` are two of these processes. That is worth holding onto while you
  decide, in Lab 03, whether this process or the channel runtime should own
  subscriptions and fan-out.

  Nothing in this module's state is durable. The message it persists is; the
  membership list it might cache is not.
  """

  use BeamSlackWeb, :channel

  alias BeamSlackWeb.Authorization

  @lab_02 """
  Lab 02 is not implemented yet. Read docs/labs/02-persist-vs-broadcast.md, then \
  replace handle_in("new_message", ...) in lib/beamslack_web/channels/channel_channel.ex.
  """

  @lab_04 """
  Lab 04 is not implemented yet. Read docs/labs/04-presence-architecture.md, then \
  replace handle_info(:after_join, ...) in lib/beamslack_web/channels/channel_channel.ex.
  """

  @lab_05 """
  Lab 05 is not implemented yet. Read docs/labs/05-typing-indicators.md, then \
  replace handle_in("typing", ...) in lib/beamslack_web/channels/channel_channel.ex.
  """

  @doc """
  Authorizes the join and puts the channel on the socket.

  Read access is enough to join. Whether *posting* additionally requires channel
  membership is Lab 02's call; `BeamSlackWeb.Authorization.fetch_writable_channel/2`
  is there when you want it.

  Lab 04 will want to send itself `:after_join` from here, because you cannot
  track presence until the join has returned.
  """
  @impl true
  def join("channel:" <> channel_id, _params, socket) do
    case Authorization.fetch_channel(channel_id, socket.assigns.current_user) do
      {:ok, channel} ->
        {:ok, %{channel_id: channel.id, name: channel.name}, assign(socket, :channel, channel)}

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  @impl true
  def handle_in("new_message", %{"body" => _body}, _socket), do: raise(@lab_02)

  def handle_in("typing", _payload, _socket), do: raise(@lab_05)

  @impl true
  def handle_info(:after_join, _socket), do: raise(@lab_04)
end
