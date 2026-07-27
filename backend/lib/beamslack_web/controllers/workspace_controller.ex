defmodule BeamSlackWeb.WorkspaceController do
  use BeamSlackWeb, :controller

  alias BeamSlack.Workspaces
  alias BeamSlackWeb.Authorization

  action_fallback BeamSlackWeb.FallbackController

  def index(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :index, workspaces: Workspaces.list_user_workspaces(user.id))
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    attrs = Map.take(params, ["name"])

    with {:ok, workspace} <- Workspaces.create_workspace(attrs, user.id) do
      conn
      |> put_status(:created)
      |> render(:show, workspace: workspace)
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, workspace} <- Authorization.fetch_workspace(id, user) do
      render(conn, :show, workspace: workspace)
    end
  end

  def members(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, workspace} <- Authorization.fetch_workspace(id, user) do
      render(conn, :members, members: Workspaces.list_members(workspace.id))
    end
  end

  @doc """
  Joins the current user to a workspace. Idempotent: joining twice returns the
  existing membership rather than a uniqueness error.
  """
  def join(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, workspace} <- Authorization.fetch_existing_workspace(id),
         {:ok, member} <- join_once(workspace.id, user.id) do
      render(conn, :member, member: member)
    end
  end

  defp join_once(workspace_id, user_id) do
    case Workspaces.get_membership(workspace_id, user_id) do
      nil -> Workspaces.join_workspace(workspace_id, user_id)
      member -> {:ok, member}
    end
  end
end
