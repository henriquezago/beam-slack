defmodule BeamSlackWeb.ChannelController do
  use BeamSlackWeb, :controller

  alias BeamSlack.Channels
  alias BeamSlackWeb.Authorization

  action_fallback BeamSlackWeb.FallbackController

  def index(conn, %{"workspace_id" => workspace_id}) do
    user = conn.assigns.current_user

    with {:ok, workspace} <- Authorization.fetch_workspace(workspace_id, user) do
      render(conn, :index, channels: Channels.list_channels(workspace.id))
    end
  end

  def create(conn, %{"workspace_id" => workspace_id} = params) do
    user = conn.assigns.current_user

    with {:ok, workspace} <- Authorization.fetch_workspace(workspace_id, user) do
      attrs =
        params
        |> Map.take(["name", "type"])
        |> Map.put("workspace_id", workspace.id)

      with {:ok, channel} <- Channels.create_channel(attrs, user.id) do
        conn
        |> put_status(:created)
        |> render(:show, channel: channel)
      end
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, channel} <- Authorization.fetch_channel(id, user) do
      render(conn, :show, channel: channel)
    end
  end

  def members(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, channel} <- Authorization.fetch_channel(id, user) do
      render(conn, :members, members: Channels.list_members(channel.id))
    end
  end

  @doc """
  Joins the current user to a public channel. Idempotent.
  """
  def join(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, channel} <- Authorization.fetch_joinable_channel(id, user),
         {:ok, member} <- join_once(channel.id, user.id) do
      render(conn, :member, member: member)
    end
  end

  defp join_once(channel_id, user_id) do
    case Channels.get_membership(channel_id, user_id) do
      nil -> Channels.join_channel(channel_id, user_id)
      member -> {:ok, member}
    end
  end
end
