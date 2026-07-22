defmodule BeamSlack.Repo.Migrations.CreateWorkspaces do
  @moduledoc """
  Migration for creating the workspaces table.
  """

  use Ecto.Migration

  @doc """
  Creates the workspaces table.
  """
  def change do
    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create index(:workspaces, [:owner_id])
    create unique_index(:workspaces, [:name, :owner_id])
  end
end
