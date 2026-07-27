defmodule BeamSlackWeb.WorkspaceJSON do
  @moduledoc """
  Renders workspaces and workspace memberships.
  """

  alias BeamSlack.Workspaces.Workspace
  alias BeamSlack.Workspaces.WorkspaceMember
  alias BeamSlackWeb.UserJSON

  def index(%{workspaces: workspaces}), do: %{data: Enum.map(workspaces, &data/1)}

  def show(%{workspace: workspace}), do: %{data: data(workspace)}

  def members(%{members: members}), do: %{data: Enum.map(members, &member_data/1)}

  def member(%{member: member}), do: %{data: member_data(member)}

  def data(%Workspace{} = workspace) do
    %{
      id: workspace.id,
      name: workspace.name,
      owner_id: workspace.owner_id,
      inserted_at: workspace.inserted_at
    }
  end

  defp member_data(%WorkspaceMember{} = member) do
    %{
      workspace_id: member.workspace_id,
      user_id: member.user_id,
      role: member.role,
      joined_at: member.joined_at,
      user: user_data(member.user)
    }
  end

  defp user_data(%Ecto.Association.NotLoaded{}), do: nil
  defp user_data(nil), do: nil
  defp user_data(user), do: UserJSON.data(user)
end
