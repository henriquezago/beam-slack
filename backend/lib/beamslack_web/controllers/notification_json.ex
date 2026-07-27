defmodule BeamSlackWeb.NotificationJSON do
  @moduledoc """
  Renders in-app notifications.
  """

  alias BeamSlack.Notifications.Notification
  alias BeamSlackWeb.UserJSON

  def index(%{notifications: notifications}) do
    %{data: Enum.map(notifications, &data/1)}
  end

  def show(%{notification: notification}), do: %{data: data(notification)}

  def unread(%{count: count}), do: %{data: %{count: count}}

  def data(%Notification{} = notification) do
    %{
      id: notification.id,
      user_id: notification.user_id,
      message_id: notification.message_id,
      channel_id: notification.channel_id,
      kind: notification.kind,
      read_at: notification.read_at,
      inserted_at: notification.inserted_at,
      message: message_data(notification.message)
    }
  end

  defp message_data(%Ecto.Association.NotLoaded{}), do: nil
  defp message_data(nil), do: nil

  defp message_data(message) do
    %{
      id: message.id,
      body: message.body,
      sender: sender_data(Map.get(message, :sender))
    }
  end

  defp sender_data(%Ecto.Association.NotLoaded{}), do: nil
  defp sender_data(nil), do: nil
  defp sender_data(sender), do: UserJSON.data(sender)
end
