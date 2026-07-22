defmodule BeamSlack.Messaging.Message do
  @moduledoc """
  Ecto schema for a message. A message is durable, belongs to a channel, and is
  authored by a sending user.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Channels.Channel

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :body, :string
    belongs_to :channel, Channel
    belongs_to :sender, User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:channel_id, :sender_id, :body])
    |> validate_required([:channel_id, :sender_id, :body])
    |> assoc_constraint(:channel)
    |> assoc_constraint(:sender)
  end
end
