defmodule BeamSlack.Messaging do
  @moduledoc """
  Messages, threads, reactions, and mention extraction.

  Messages are durable and live in PostgreSQL. Mentions are derived at write time
  from `@name` tokens in the body and stored as rows, so renaming a user does not
  rewrite history — the mention still points at the right person by id.
  """

  import Ecto.Query

  alias BeamSlack.Accounts.User
  alias BeamSlack.Events
  alias BeamSlack.Messaging.Mention
  alias BeamSlack.Messaging.Message
  alias BeamSlack.Messaging.Reaction
  alias BeamSlack.Notifications
  alias BeamSlack.Repo

  @doc """
  Sends (persists) a top-level channel message.

  Detects `@name` mentions, creates mention rows, and enqueues in-app
  notifications. Emits `[:beamslack, :message, :sent]` on success.

  Note that a telemetry event is not the domain broadcast Lab 02 asks about.
  """
  def send_message(attrs) do
    BeamSlack.Telemetry.span_message_send(fn ->
      attrs
      |> Map.delete(:thread_root_id)
      |> Map.delete("thread_root_id")
      |> do_insert_message()
    end)
  end

  @doc """
  Posts a reply in a thread rooted at `thread_root_id`.

  The root must be a top-level message in the same channel. Updates the root's
  `reply_count` and `last_reply_at` in the same transaction.
  """
  def reply_to_message(attrs) do
    root_id = attrs[:thread_root_id] || attrs["thread_root_id"]
    channel_id = attrs[:channel_id] || attrs["channel_id"]

    with {:ok, root} <- fetch_thread_root(root_id, channel_id) do
      Repo.transaction(fn -> insert_reply!(root, attrs) end)
    end
  end

  defp insert_reply!(root, attrs) do
    case do_insert_message(attrs) do
      {:ok, reply} ->
        {:ok, updated_root} =
          root
          |> Ecto.Changeset.change(%{
            reply_count: root.reply_count + 1,
            last_reply_at: reply.inserted_at
          })
          |> Repo.update()

        reply = Repo.preload(reply, [:sender, :reactions, :mentions])
        Events.thread_reply(reply.channel_id, reply, updated_root)
        notify_thread_participants(updated_root, reply)
        reply

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Lists top-level messages in a channel (replies are excluded), oldest-first.

  Accepts an optional `:limit`. A limit returns the *most recent* N top-level
  messages, still ordered oldest-first.
  """
  def list_messages(channel_id, opts \\ []) do
    query =
      Message
      |> where(channel_id: ^channel_id)
      |> where([m], is_nil(m.thread_root_id))
      |> preload([:sender, :reactions, :mentions])

    case Keyword.get(opts, :limit) do
      nil ->
        query |> order_by(asc: :inserted_at, asc: :id) |> Repo.all()

      limit ->
        query
        |> order_by(desc: :inserted_at, desc: :id)
        |> limit(^limit)
        |> Repo.all()
        |> Enum.reverse()
    end
  end

  @doc """
  Lists replies in a thread, oldest-first.
  """
  def list_thread_replies(thread_root_id) do
    Message
    |> where(thread_root_id: ^thread_root_id)
    |> order_by(asc: :inserted_at, asc: :id)
    |> preload([:sender, :reactions, :mentions])
    |> Repo.all()
  end

  @doc """
  Fetches one message by id, or `nil`.
  """
  def get_message(id) do
    Message
    |> where(id: ^id)
    |> preload([:sender, :reactions, :mentions])
    |> Repo.one()
  end

  @doc """
  Adds a reaction. Idempotent: repeating the same user/message/emoji returns the
  existing row as `{:ok, reaction}`.
  """
  def add_reaction(message_id, user_id, emoji) do
    with {:ok, message} <- fetch_message(message_id) do
      insert_or_fetch_reaction(message, message_id, user_id, emoji)
    end
  end

  defp insert_or_fetch_reaction(message, message_id, user_id, emoji) do
    changeset =
      Reaction.changeset(%Reaction{}, %{
        message_id: message_id,
        user_id: user_id,
        emoji: emoji
      })

    case Repo.insert(changeset) do
      {:ok, reaction} ->
        broadcast_reactions(message)
        {:ok, reaction}

      {:error, changeset} ->
        resolve_reaction_conflict(changeset, message, message_id, user_id, emoji)
    end
  end

  defp resolve_reaction_conflict(changeset, message, message_id, user_id, emoji) do
    if unique_reaction_error?(changeset) do
      reaction =
        Reaction
        |> where(message_id: ^message_id, user_id: ^user_id, emoji: ^emoji)
        |> Repo.one!()

      broadcast_reactions(message)
      {:ok, reaction}
    else
      {:error, changeset}
    end
  end

  defp unique_reaction_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {_field, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  @doc """
  Removes a user's reaction. Idempotent: returns `:ok` even when nothing matched.
  """
  def remove_reaction(message_id, user_id, emoji) do
    with {:ok, message} <- fetch_message(message_id) do
      Reaction
      |> where(message_id: ^message_id, user_id: ^user_id, emoji: ^emoji)
      |> Repo.delete_all()

      broadcast_reactions(message)
      :ok
    end
  end

  @doc """
  Summarizes reactions on a message as `[%{emoji, count, user_ids, reacted}]`.

  `viewer_id` marks which ones the current user has applied.
  """
  def reaction_summary(message_or_id, viewer_id \\ nil)

  def reaction_summary(%Message{reactions: reactions}, viewer_id)
      when is_list(reactions) do
    summarize_reactions(reactions, viewer_id)
  end

  def reaction_summary(message_id, viewer_id) when is_binary(message_id) do
    reactions = Reaction |> where(message_id: ^message_id) |> Repo.all()
    summarize_reactions(reactions, viewer_id)
  end

  @doc "The emoji a reaction may use."
  def reaction_emojis, do: Reaction.emojis()

  defp do_insert_message(attrs) do
    changeset = Message.changeset(%Message{}, attrs)

    case Repo.insert(changeset) do
      {:ok, message} ->
        message = Repo.preload(message, [:sender, :reactions, :mentions])
        mentioned = create_mentions(message)
        notify_mentions(message, mentioned)
        {:ok, Repo.preload(message, [:sender, :reactions, :mentions], force: true)}

      error ->
        error
    end
  end

  defp create_mentions(%Message{body: body, id: message_id, sender_id: sender_id}) do
    names = extract_mention_names(body)

    users =
      User
      |> where([u], u.name in ^names)
      |> where([u], u.id != ^sender_id)
      |> Repo.all()

    Enum.map(users, fn user ->
      %Mention{}
      |> Mention.changeset(%{message_id: message_id, user_id: user.id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:message_id, :user_id])

      user
    end)
  end

  defp extract_mention_names(body) when is_binary(body) do
    ~r/@([a-zA-Z0-9_\-\.]+)/
    |> Regex.scan(body)
    |> Enum.map(fn [_full, name] -> name end)
    |> Enum.uniq()
  end

  defp extract_mention_names(_body), do: []

  defp notify_mentions(message, users) do
    Enum.each(users, fn user ->
      Notifications.notify_mention(user.id, message)
    end)
  end

  defp notify_thread_participants(root, reply) do
    participant_ids =
      ([root.sender_id] ++
         (Message
          |> where(thread_root_id: ^root.id)
          |> select([m], m.sender_id)
          |> Repo.all()))
      |> Enum.uniq()
      |> Enum.reject(&(&1 == reply.sender_id))

    Enum.each(participant_ids, fn user_id ->
      Notifications.notify_thread_reply(user_id, reply)
    end)
  end

  defp fetch_thread_root(nil, _channel_id), do: {:error, :not_found}

  defp fetch_thread_root(root_id, channel_id) do
    case get_message(root_id) do
      %Message{thread_root_id: nil, channel_id: ^channel_id} = root ->
        {:ok, root}

      %Message{thread_root_id: nil} ->
        {:error, :wrong_channel}

      %Message{} ->
        # Replies cannot themselves be thread roots.
        {:error, :not_a_root}

      nil ->
        {:error, :not_found}
    end
  end

  defp fetch_message(id) do
    case get_message(id) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  defp broadcast_reactions(message) do
    summary = reaction_summary(message.id)
    Events.reactions_changed(message.channel_id, message.id, summary)
  end

  defp summarize_reactions(reactions, viewer_id) do
    reactions
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, group} ->
      user_ids = Enum.map(group, & &1.user_id)

      %{
        emoji: emoji,
        count: length(group),
        user_ids: user_ids,
        reacted: viewer_id != nil and viewer_id in user_ids
      }
    end)
    |> Enum.sort_by(& &1.emoji)
  end
end
