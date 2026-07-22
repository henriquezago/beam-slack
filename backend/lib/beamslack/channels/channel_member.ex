defmodule BeamSlack.Channels.ChannelMember do
  @moduledoc """
  Ecto schema for channel membership. Tracks which users belong to a channel,
  used for private channels and membership tracking generally.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Channels.Channel

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_members" do
    field :joined_at, :utc_datetime
    belongs_to :channel, Channel
    belongs_to :user, User
    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:channel_id, :user_id, :joined_at])
    |> validate_required([:channel_id, :user_id])
    |> put_joined_at()
    |> assoc_constraint(:channel)
    |> assoc_constraint(:user)
    |> unique_constraint([:channel_id, :user_id],
      name: :channel_members_channel_id_user_id_index
    )
  end

  defp put_joined_at(changeset) do
    if get_field(changeset, :joined_at) do
      changeset
    else
      put_change(changeset, :joined_at, DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end
end
