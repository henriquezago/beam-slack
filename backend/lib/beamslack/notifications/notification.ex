defmodule BeamSlack.Notifications.Notification do
  @moduledoc """
  Ecto schema for an in-app notification.

  Unread state is `read_at` being null rather than a boolean, because "when" is
  strictly more information than "whether" and costs the same column.

  The unique index on `{user_id, message_id, kind}` makes creation idempotent,
  which matters more than it looks: it means the notification path can be retried
  safely, and that is precisely the property Lab 13 asks you to reason about.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Channels.Channel
  alias BeamSlack.Messaging.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @kinds ~w(mention thread_reply)

  schema "notifications" do
    field :kind, :string
    field :read_at, :utc_datetime_usec
    belongs_to :user, User
    belongs_to :message, Message
    belongs_to :channel, Channel
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The reasons a notification can exist."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :message_id, :channel_id, :kind, :read_at])
    |> validate_required([:user_id, :message_id, :channel_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> assoc_constraint(:user)
    |> assoc_constraint(:message)
    |> assoc_constraint(:channel)
    |> unique_constraint([:user_id, :message_id, :kind],
      name: :notifications_user_id_message_id_kind_index
    )
  end
end
