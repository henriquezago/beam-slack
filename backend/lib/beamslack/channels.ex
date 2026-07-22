defmodule BeamSlack.Channels do
  @moduledoc """
  The Channels context. Handles creating channels within a workspace and
  managing channel membership.

  All state here is durable and lives in PostgreSQL.
  """

  import Ecto.Query

  alias BeamSlack.Channels.Channel
  alias BeamSlack.Channels.ChannelMember
  alias BeamSlack.Repo

  @doc """
  Creates a channel in a workspace.

  When `creator_id` is provided, the creator is added as a channel member in the
  same transaction as the channel insert.
  """
  def create_channel(attrs, creator_id \\ nil)

  def create_channel(attrs, nil) do
    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
  end

  def create_channel(attrs, creator_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:channel, Channel.changeset(%Channel{}, attrs))
    |> Ecto.Multi.insert(:membership, fn %{channel: channel} ->
      ChannelMember.changeset(%ChannelMember{}, %{
        channel_id: channel.id,
        user_id: creator_id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} -> {:ok, channel}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Adds `user_id` to `channel_id`.
  """
  def join_channel(channel_id, user_id) do
    %ChannelMember{}
    |> ChannelMember.changeset(%{channel_id: channel_id, user_id: user_id})
    |> Repo.insert()
  end

  @doc """
  Returns the channel with the given id, or nil if it does not exist.
  """
  def get_channel(id), do: Repo.get(Channel, id)

  @doc """
  Lists the channels belonging to a workspace, ordered by name.
  """
  def list_channels(workspace_id) do
    Channel
    |> where(workspace_id: ^workspace_id)
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Lists the members of a channel with their associated users preloaded.
  """
  def list_members(channel_id) do
    ChannelMember
    |> where(channel_id: ^channel_id)
    |> order_by(:joined_at)
    |> preload(:user)
    |> Repo.all()
  end
end
