defmodule BeamSlack.Messaging do
  @moduledoc """
  The Messaging context. Handles sending messages to channels and listing a
  channel's message history.

  Messages are durable and live in PostgreSQL. In Phase 1 sending is fully
  synchronous: a message is only considered sent once the transaction commits.
  """

  import Ecto.Query

  alias BeamSlack.Messaging.Message
  alias BeamSlack.Repo

  @doc """
  Sends (persists) a message. Expects `%{channel_id, sender_id, body}`.
  """
  def send_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists the messages in a channel ordered oldest-first, with the sender
  preloaded.

  Accepts an optional `:limit` to cap the number of returned messages.
  """
  def list_messages(channel_id, opts \\ []) do
    query =
      Message
      |> where(channel_id: ^channel_id)
      |> order_by(asc: :inserted_at, asc: :id)
      |> preload(:sender)

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> limit(query, ^limit)
      end

    Repo.all(query)
  end
end
