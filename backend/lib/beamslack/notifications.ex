defmodule BeamSlack.Notifications do
  @moduledoc """
  In-app notifications.

  Creating a notification is durable and idempotent (unique on user + message +
  kind). Broadcasting it to the user's devices is the side effect Lab 13 asks you
  to place carefully: today it happens inline via `BeamSlack.Events`, which is the
  simplest choice and almost certainly the wrong long-term one.
  """

  import Ecto.Query

  alias BeamSlack.Events
  alias BeamSlack.Messaging.Message
  alias BeamSlack.Notifications.Notification
  alias BeamSlack.Repo

  @doc """
  Records a mention notification and broadcasts it.
  """
  def notify_mention(user_id, %Message{} = message) do
    create_and_broadcast(%{
      user_id: user_id,
      message_id: message.id,
      channel_id: message.channel_id,
      kind: "mention"
    })
  end

  @doc """
  Records a thread-reply notification and broadcasts it.
  """
  def notify_thread_reply(user_id, %Message{} = reply) do
    create_and_broadcast(%{
      user_id: user_id,
      message_id: reply.id,
      channel_id: reply.channel_id,
      kind: "thread_reply"
    })
  end

  @doc """
  Lists a user's notifications, newest first. Unread ones first within the same
  second is not required — clients sort by `inserted_at`.
  """
  def list_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Notification
    |> where(user_id: ^user_id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(^limit)
    |> preload(message: :sender)
    |> Repo.all()
  end

  @doc """
  Marks one notification as read. Idempotent.
  """
  def mark_read(notification_id, user_id) do
    case Repo.get_by(Notification, id: notification_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      %Notification{read_at: nil} = notification ->
        notification
        |> Notification.changeset(%{read_at: DateTime.utc_now(:microsecond)})
        |> Repo.update()

      notification ->
        {:ok, notification}
    end
  end

  @doc """
  Marks every unread notification for the user as read.
  """
  def mark_all_read(user_id) do
    now = DateTime.utc_now(:microsecond)

    {count, _} =
      Notification
      |> where(user_id: ^user_id)
      |> where([n], is_nil(n.read_at))
      |> Repo.update_all(set: [read_at: now])

    {:ok, count}
  end

  @doc """
  How many unread notifications the user has.
  """
  def unread_count(user_id) do
    Notification
    |> where(user_id: ^user_id)
    |> where([n], is_nil(n.read_at))
    |> Repo.aggregate(:count)
  end

  defp create_and_broadcast(attrs) do
    case %Notification{}
         |> Notification.changeset(attrs)
         |> Repo.insert(
           on_conflict: :nothing,
           conflict_target: [:user_id, :message_id, :kind],
           returning: true
         ) do
      {:ok, %Notification{id: nil}} ->
        # Already existed. Fetch and broadcast again so a reconnecting client can
        # catch up if the first broadcast was lost — Lab 13 may change this.
        notification =
          Notification
          |> where(
            user_id: ^attrs.user_id,
            message_id: ^attrs.message_id,
            kind: ^attrs.kind
          )
          |> preload(message: :sender)
          |> Repo.one!()

        Events.notification_created(notification)
        {:ok, notification}

      {:ok, notification} ->
        notification = Repo.preload(notification, message: :sender)
        Events.notification_created(notification)
        {:ok, notification}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
