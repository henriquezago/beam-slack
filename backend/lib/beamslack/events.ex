defmodule BeamSlack.Events do
  @moduledoc """
  Where Track 5's features publish what they did.

  ## Read this before Lab 03

  This module makes a topic-taxonomy decision, and Lab 03 asks you to make that
  decision yourself. The two are not in conflict, but you should know what is here
  before you design yours:

    * `"channel:<id>"` carries things every member of a channel should see:
      reactions, thread reply counts.
    * `"user:<id>"` carries things only one person should see: notifications.

  If Lab 03 leads you somewhere else, change these two functions and the frontend
  hook that subscribes. Nothing else depends on the shape.

  ## What is deliberately not here

  New messages. Where a message broadcast is emitted from, and whether it happens
  before or after the insert, is Lab 02's decision and stays in
  `BeamSlackWeb.ChannelChannel` until you make it.

  ## The failure boundary

  Every function here can fail — PubSub can be down, the endpoint can be
  restarting — and every one of them is called from inside a request that has
  already succeeded at the thing the user asked for. What that should mean is
  Lab 13. Right now they are called synchronously and inline, which is the
  simplest possible choice and almost certainly the wrong one.
  """

  alias BeamSlackWeb.Endpoint
  alias BeamSlackWeb.MessageJSON
  alias BeamSlackWeb.NotificationJSON
  alias BeamSlackWeb.ReactionJSON

  @doc """
  Announces that a message's reactions changed.

  Sends the full reaction summary rather than a delta, because a client that
  missed one event would otherwise stay wrong forever, and the payload is small.
  """
  @spec reactions_changed(String.t(), String.t(), [map()]) :: :ok
  def reactions_changed(channel_id, message_id, summary) do
    broadcast("channel:#{channel_id}", "reactions_changed", %{
      message_id: message_id,
      reactions: Enum.map(summary, &ReactionJSON.summary_data/1)
    })
  end

  @doc """
  Announces a reply in a thread, so channel members can update the root's
  "N replies" without refetching.
  """
  @spec thread_reply(String.t(), struct(), map()) :: :ok
  def thread_reply(channel_id, reply, root_summary) do
    broadcast("channel:#{channel_id}", "thread_reply", %{
      reply: MessageJSON.data(reply),
      thread_root_id: root_summary.id,
      reply_count: root_summary.reply_count,
      last_reply_at: root_summary.last_reply_at
    })
  end

  @doc """
  Delivers a notification to one user, on every device they have connected.

  The topic is per-user rather than per-connection, which is the whole reason the
  socket joins it: a user with four tabs gets four deliveries from one broadcast,
  and PubSub does the fan-out.
  """
  @spec notification_created(struct()) :: :ok
  def notification_created(notification) do
    broadcast(
      "user:#{notification.user_id}",
      "notification",
      NotificationJSON.data(notification)
    )
  end

  defp broadcast(topic, event, payload) do
    Endpoint.broadcast(topic, event, payload)
    :ok
  end
end
