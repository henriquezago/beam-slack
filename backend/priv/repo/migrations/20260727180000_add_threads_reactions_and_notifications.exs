defmodule BeamSlack.Repo.Migrations.AddThreadsReactionsAndNotifications do
  @moduledoc """
  Track 5's durable state: threads, reactions, mentions, and notifications.

  Threads are a self-reference on messages rather than a separate table. A reply
  points at the message that started the thread, not at the message it is
  answering, so a thread is one query rather than a recursive walk. That rules out
  arbitrarily nested replies, which is a product decision Slack also made.
  """

  use Ecto.Migration

  def change do
    alter table(:messages) do
      # Null for a top-level message; the thread's first message otherwise.
      add :thread_root_id, references(:messages, type: :binary_id, on_delete: :delete_all)
      # Denormalized so a channel listing does not need a join per message.
      add :reply_count, :integer, null: false, default: 0
      add :last_reply_at, :utc_datetime_usec
    end

    create index(:messages, [:thread_root_id, :inserted_at])

    create table(:reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # One of each emoji per user per message. Enforced in the database rather than
    # only in a changeset, because two concurrent requests both pass a changeset
    # check and only the database sees both at once.
    create unique_index(:reactions, [:message_id, :user_id, :emoji])
    create index(:reactions, [:message_id])

    create table(:mentions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:mentions, [:message_id, :user_id])
    create index(:mentions, [:user_id])

    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :read_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notifications, [:user_id, :read_at])
    create unique_index(:notifications, [:user_id, :message_id, :kind])
  end
end
