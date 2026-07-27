defmodule BeamSlack.Messaging.Message do
  @moduledoc """
  Ecto schema for a message. A message is durable, belongs to a channel, and is
  authored by a sending user.

  ## Threads

  A reply carries `thread_root_id` pointing at the message that *started* the
  thread, not at the message it answers. So a thread is one indexed query rather
  than a recursive walk, at the cost of not supporting arbitrary nesting. Slack
  made the same trade.

  `reply_count` and `last_reply_at` are denormalized onto the root so that listing
  a channel does not need a join or a subquery per message. They are maintained by
  `BeamSlack.Messaging.reply_to_message/1` inside the same transaction as the
  insert, which is the only way they stay true.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Channels.Channel
  alias BeamSlack.Messaging.Mention
  alias BeamSlack.Messaging.Reaction

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "messages" do
    field :body, :string
    field :reply_count, :integer, default: 0
    field :last_reply_at, :utc_datetime_usec
    belongs_to :channel, Channel
    belongs_to :sender, User
    belongs_to :thread_root, __MODULE__
    has_many :replies, __MODULE__, foreign_key: :thread_root_id
    has_many :reactions, Reaction
    has_many :mentions, Mention
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:channel_id, :sender_id, :body, :thread_root_id])
    |> validate_required([:channel_id, :sender_id, :body])
    |> assoc_constraint(:channel)
    |> assoc_constraint(:sender)
    |> assoc_constraint(:thread_root)
  end
end
