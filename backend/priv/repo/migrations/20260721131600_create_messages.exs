defmodule BeamSlack.Repo.Migrations.CreateMessages do
  @moduledoc """
  Migration for creating the messages table.
  """

  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sender_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:channel_id, :inserted_at])
    create index(:messages, [:sender_id])
  end
end
