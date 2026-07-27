defmodule BeamSlackWeb.MessageJSON do
  @moduledoc """
  Renders messages, embedding the sender and a reaction summary when available.
  """

  alias BeamSlack.Messaging
  alias BeamSlack.Messaging.Message
  alias BeamSlackWeb.ReactionJSON
  alias BeamSlackWeb.UserJSON

  def index(%{messages: messages, current_user: user}) do
    %{data: Enum.map(messages, &data(&1, user && user.id))}
  end

  def index(%{messages: messages}), do: %{data: Enum.map(messages, &data/1)}

  def show(%{message: message, current_user: user}) do
    %{data: data(message, user && user.id)}
  end

  def show(%{message: message}), do: %{data: data(message)}

  def data(%Message{} = message), do: data(message, nil)

  def data(%Message{} = message, viewer_id) do
    %{
      id: message.id,
      channel_id: message.channel_id,
      sender_id: message.sender_id,
      body: message.body,
      thread_root_id: message.thread_root_id,
      reply_count: message.reply_count || 0,
      last_reply_at: message.last_reply_at,
      inserted_at: message.inserted_at,
      sender: sender_data(message.sender),
      reactions: reaction_data(message, viewer_id),
      mention_user_ids: mention_ids(message)
    }
  end

  defp sender_data(%Ecto.Association.NotLoaded{}), do: nil
  defp sender_data(nil), do: nil
  defp sender_data(sender), do: UserJSON.data(sender)

  defp reaction_data(%Message{reactions: %Ecto.Association.NotLoaded{}}, _viewer_id), do: []

  defp reaction_data(%Message{} = message, viewer_id) do
    message
    |> Messaging.reaction_summary(viewer_id)
    |> Enum.map(&ReactionJSON.summary_data/1)
  end

  defp mention_ids(%Message{mentions: %Ecto.Association.NotLoaded{}}), do: []

  defp mention_ids(%Message{mentions: mentions}) when is_list(mentions),
    do: Enum.map(mentions, & &1.user_id)

  defp mention_ids(_), do: []
end
