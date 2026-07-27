defmodule BeamSlackWeb.ChannelJSON do
  @moduledoc """
  Renders channels and channel memberships.
  """

  alias BeamSlack.Channels.Channel
  alias BeamSlack.Channels.ChannelMember
  alias BeamSlackWeb.UserJSON

  def index(%{channels: channels}), do: %{data: Enum.map(channels, &data/1)}

  def show(%{channel: channel}), do: %{data: data(channel)}

  def members(%{members: members}), do: %{data: Enum.map(members, &member_data/1)}

  def member(%{member: member}), do: %{data: member_data(member)}

  def data(%Channel{} = channel) do
    %{
      id: channel.id,
      workspace_id: channel.workspace_id,
      name: channel.name,
      type: channel.type,
      inserted_at: channel.inserted_at
    }
  end

  defp member_data(%ChannelMember{} = member) do
    %{
      channel_id: member.channel_id,
      user_id: member.user_id,
      joined_at: member.joined_at,
      user: user_data(member.user)
    }
  end

  defp user_data(%Ecto.Association.NotLoaded{}), do: nil
  defp user_data(nil), do: nil
  defp user_data(user), do: UserJSON.data(user)
end
