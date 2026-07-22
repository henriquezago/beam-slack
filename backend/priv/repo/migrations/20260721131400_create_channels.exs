defmodule BeamSlack.Repo.Migrations.CreateChannels do
  @moduledoc """
  Migration for creating the channels table.
  """

  use Ecto.Migration

  def change do
    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :type, :string, null: false, default: "public"
      timestamps(type: :utc_datetime)
    end

    create index(:channels, [:workspace_id])
    create unique_index(:channels, [:workspace_id, :name])
  end
end
