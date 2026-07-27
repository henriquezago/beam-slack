defmodule BeamSlackWeb.MessageController do
  use BeamSlackWeb, :controller

  alias BeamSlack.Messaging
  alias BeamSlackWeb.Authorization

  action_fallback BeamSlackWeb.FallbackController

  @default_limit 50
  @max_limit 200

  def index(conn, %{"channel_id" => channel_id} = params) do
    user = conn.assigns.current_user

    with {:ok, channel} <- Authorization.fetch_channel(channel_id, user) do
      messages = Messaging.list_messages(channel.id, limit: limit(params))
      render(conn, :index, messages: messages, current_user: user)
    end
  end

  @doc """
  Persists a top-level message or a thread reply when `thread_root_id` is set.
  """
  def create(conn, %{"channel_id" => channel_id} = params) do
    user = conn.assigns.current_user

    attrs = %{
      channel_id: channel_id,
      sender_id: user.id,
      body: params["body"],
      thread_root_id: params["thread_root_id"]
    }

    with {:ok, channel} <- Authorization.fetch_writable_channel(channel_id, user),
         {:ok, message} <- insert_message(channel, attrs) do
      conn
      |> put_status(:created)
      |> render(:show, message: message, current_user: user)
    end
  end

  def thread(conn, %{"id" => message_id}) do
    user = conn.assigns.current_user

    with {:ok, root} <- fetch_readable_message(message_id, user) do
      replies = Messaging.list_thread_replies(root.id)

      conn
      |> put_view(json: BeamSlackWeb.MessageJSON)
      |> render(:index, messages: [root | replies], current_user: user)
    end
  end

  def add_reaction(conn, %{"id" => message_id, "emoji" => emoji}) do
    user = conn.assigns.current_user

    with {:ok, message} <- fetch_writable_message(message_id, user),
         {:ok, _reaction} <- Messaging.add_reaction(message.id, user.id, emoji) do
      summary = Messaging.reaction_summary(message.id, user.id)

      json(conn, %{data: Enum.map(summary, &BeamSlackWeb.ReactionJSON.summary_data/1)})
    end
  end

  def remove_reaction(conn, %{"id" => message_id, "emoji" => emoji}) do
    user = conn.assigns.current_user

    with {:ok, message} <- fetch_writable_message(message_id, user),
         :ok <- Messaging.remove_reaction(message.id, user.id, emoji) do
      summary = Messaging.reaction_summary(message.id, user.id)

      json(conn, %{data: Enum.map(summary, &BeamSlackWeb.ReactionJSON.summary_data/1)})
    end
  end

  def remove_reaction(_conn, _params), do: {:error, :not_found}

  defp insert_message(channel, %{thread_root_id: root_id} = attrs)
       when is_binary(root_id) and root_id != "" do
    Messaging.reply_to_message(Map.put(attrs, :channel_id, channel.id))
  end

  defp insert_message(channel, attrs) do
    Messaging.send_message(Map.put(attrs, :channel_id, channel.id))
  end

  defp fetch_readable_message(message_id, user) do
    case Messaging.get_message(message_id) do
      nil ->
        {:error, :not_found}

      message ->
        with {:ok, _channel} <- Authorization.fetch_channel(message.channel_id, user) do
          {:ok, message}
        end
    end
  end

  defp fetch_writable_message(message_id, user) do
    case Messaging.get_message(message_id) do
      nil ->
        {:error, :not_found}

      message ->
        with {:ok, _channel} <- Authorization.fetch_writable_channel(message.channel_id, user) do
          {:ok, message}
        end
    end
  end

  defp limit(params) do
    case Integer.parse(to_string(params["limit"] || "")) do
      {value, _rest} when value > 0 -> min(value, @max_limit)
      _ -> @default_limit
    end
  end
end
