defmodule BeamSlackWeb.Authorization do
  @moduledoc """
  Resource lookup plus access control for the JSON API.

  Every controller action that operates on a workspace or channel goes through
  here, so the rules live in one place:

    * a workspace is visible to its members
    * a public channel is visible to any member of its workspace
    * a private channel is visible only to its own members
    * a user may self-join a workspace, or a public channel in a workspace they
      already belong to; private channels require an invitation, which does not
      exist yet

  Lookups return `{:error, :not_found}` rather than raising for ids that are not
  well-formed UUIDs, so a malformed URL is a 404 and not a 500.
  """

  alias BeamSlack.Channels
  alias BeamSlack.Workspaces

  @type actor :: %{id: String.t()}

  @doc """
  Fetches a workspace the actor is a member of.
  """
  @spec fetch_workspace(String.t(), actor) ::
          {:ok, struct()} | {:error, :not_found | :forbidden}
  def fetch_workspace(workspace_id, actor) do
    with {:ok, workspace} <- fetch_existing_workspace(workspace_id) do
      if Workspaces.member?(workspace.id, actor.id) do
        {:ok, workspace}
      else
        {:error, :forbidden}
      end
    end
  end

  @doc """
  Fetches a workspace without any membership requirement. Used by join, where the
  actor is by definition not a member yet.
  """
  @spec fetch_existing_workspace(String.t()) :: {:ok, struct()} | {:error, :not_found}
  def fetch_existing_workspace(workspace_id) do
    if uuid?(workspace_id) do
      case Workspaces.get_workspace(workspace_id) do
        nil -> {:error, :not_found}
        workspace -> {:ok, workspace}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Fetches a channel the actor is allowed to read.
  """
  @spec fetch_channel(String.t(), actor) :: {:ok, struct()} | {:error, :not_found | :forbidden}
  def fetch_channel(channel_id, actor) do
    with {:ok, channel} <- fetch_existing_channel(channel_id) do
      cond do
        not Workspaces.member?(channel.workspace_id, actor.id) ->
          {:error, :forbidden}

        channel.type == "private" and not Channels.member?(channel.id, actor.id) ->
          {:error, :forbidden}

        true ->
          {:ok, channel}
      end
    end
  end

  @doc """
  Fetches a channel the actor is allowed to post in, which additionally requires
  channel membership.
  """
  @spec fetch_writable_channel(String.t(), actor) ::
          {:ok, struct()} | {:error, :not_found | :forbidden}
  def fetch_writable_channel(channel_id, actor) do
    with {:ok, channel} <- fetch_channel(channel_id, actor) do
      if Channels.member?(channel.id, actor.id) do
        {:ok, channel}
      else
        {:error, :forbidden}
      end
    end
  end

  @doc """
  Fetches a channel the actor is allowed to self-join: it must be public and in a
  workspace they already belong to.
  """
  @spec fetch_joinable_channel(String.t(), actor) ::
          {:ok, struct()} | {:error, :not_found | :forbidden}
  def fetch_joinable_channel(channel_id, actor) do
    with {:ok, channel} <- fetch_existing_channel(channel_id) do
      cond do
        not Workspaces.member?(channel.workspace_id, actor.id) -> {:error, :forbidden}
        channel.type == "private" -> {:error, :forbidden}
        true -> {:ok, channel}
      end
    end
  end

  defp fetch_existing_channel(channel_id) do
    if uuid?(channel_id) do
      case Channels.get_channel(channel_id) do
        nil -> {:error, :not_found}
        channel -> {:ok, channel}
      end
    else
      {:error, :not_found}
    end
  end

  defp uuid?(id) when is_binary(id), do: match?({:ok, _}, Ecto.UUID.cast(id))
  defp uuid?(_id), do: false
end
