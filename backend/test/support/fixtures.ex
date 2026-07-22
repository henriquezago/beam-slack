defmodule BeamSlack.Fixtures do
  @moduledoc """
  Shared test fixtures for the BeamSlack domain contexts.
  """

  alias BeamSlack.Accounts
  alias BeamSlack.Channels
  alias BeamSlack.Workspaces

  def unique_suffix, do: System.unique_integer([:positive])

  def user_fixture(attrs \\ %{}) do
    n = unique_suffix()

    {:ok, user} =
      attrs
      |> Enum.into(%{
        name: "user_#{n}",
        email: "user_#{n}@example.com",
        password: "password123"
      })
      |> Accounts.register_user()

    user
  end

  def workspace_fixture(owner \\ nil, attrs \\ %{}) do
    owner = owner || user_fixture()
    attrs = Enum.into(attrs, %{name: "workspace_#{unique_suffix()}"})
    {:ok, workspace} = Workspaces.create_workspace(attrs, owner.id)
    {workspace, owner}
  end

  def channel_fixture(workspace, attrs \\ %{}, creator_id \\ nil) do
    attrs =
      attrs
      |> Enum.into(%{name: "channel_#{unique_suffix()}", type: "public"})
      |> Map.put(:workspace_id, workspace.id)

    {:ok, channel} = Channels.create_channel(attrs, creator_id)
    channel
  end
end
