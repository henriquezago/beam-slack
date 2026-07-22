defmodule BeamSlack.Repo.Migrations.CreateChannelMembers do
  @moduledoc """
  Migration for creating the channel_members table.
  """

  use Ecto.Migration

  def change do
    create table(:channel_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :joined_at, :utc_datetime, null: false, default: fragment("CURRENT_TIMESTAMP")
      timestamps(type: :utc_datetime)
    end

    create index(:channel_members, [:user_id])
    create unique_index(:channel_members, [:channel_id, :user_id])
  end
end
