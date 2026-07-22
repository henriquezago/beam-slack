defmodule BeamSlack.Repo.Migrations.CreateWorkspaceMembers do
  @moduledoc """
  Migration for creating the workspace_members table.
  """

  use Ecto.Migration

  @doc """
  Creates the workspace_members table.
  """
  def change do
    create table(:workspace_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :joined_at, :utc_datetime, null: false, default: fragment("CURRENT_TIMESTAMP")
      timestamps(type: :utc_datetime)
    end

    create index(:workspace_members, [:user_id])
    create unique_index(:workspace_members, [:workspace_id, :user_id])
  end
end
