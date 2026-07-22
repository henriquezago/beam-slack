defmodule BeamSlack.Workspaces do
  @moduledoc """
  The Workspaces context. Handles creating workspaces and managing membership.

  All state here is durable and lives in PostgreSQL.
  """

  import Ecto.Query

  alias BeamSlack.Repo
  alias BeamSlack.Workspaces.Workspace
  alias BeamSlack.Workspaces.WorkspaceMember

  @doc """
  Creates a workspace owned by `owner_id` and adds that owner as a member with
  the `owner` role.

  The workspace and the owner membership are created atomically: if either
  insert fails, neither is committed.
  """
  def create_workspace(attrs, owner_id) do
    workspace_changeset =
      %Workspace{}
      |> Workspace.changeset(Map.put(normalize(attrs), "owner_id", owner_id))

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:workspace, workspace_changeset)
    |> Ecto.Multi.insert(:membership, fn %{workspace: workspace} ->
      WorkspaceMember.changeset(%WorkspaceMember{}, %{
        workspace_id: workspace.id,
        user_id: owner_id,
        role: "owner"
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{workspace: workspace}} -> {:ok, workspace}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Adds `user_id` to `workspace_id` with the given `role` (defaults to `member`).
  """
  def join_workspace(workspace_id, user_id, role \\ "member") do
    %WorkspaceMember{}
    |> WorkspaceMember.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Returns the workspace with the given id, or nil if it does not exist.
  """
  def get_workspace(id), do: Repo.get(Workspace, id)

  @doc """
  Returns all workspaces.
  """
  def list_workspaces, do: Repo.all(Workspace)

  @doc """
  Lists the members of a workspace with their associated users preloaded.
  """
  def list_members(workspace_id) do
    WorkspaceMember
    |> where(workspace_id: ^workspace_id)
    |> order_by(:joined_at)
    |> preload(:user)
    |> Repo.all()
  end

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
