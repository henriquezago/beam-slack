defmodule BeamSlack.ChannelsTest do
  @moduledoc """
  Tests for the Channels context.
  """

  use BeamSlack.DataCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Channels
  alias BeamSlack.Channels.Channel

  describe "create_channel/2" do
    test "creates a channel in a workspace" do
      {workspace, _owner} = workspace_fixture()

      assert {:ok, %Channel{} = channel} =
               Channels.create_channel(%{workspace_id: workspace.id, name: "general"})

      assert channel.name == "general"
      assert channel.type == "public"
      assert channel.workspace_id == workspace.id
    end

    test "adds the creator as a member when creator_id is given" do
      {workspace, owner} = workspace_fixture()

      assert {:ok, channel} =
               Channels.create_channel(
                 %{workspace_id: workspace.id, name: "general"},
                 owner.id
               )

      assert [member] = Channels.list_members(channel.id)
      assert member.user_id == owner.id
    end

    test "enforces unique channel name per workspace" do
      {workspace, _owner} = workspace_fixture()
      assert {:ok, _} = Channels.create_channel(%{workspace_id: workspace.id, name: "general"})

      assert {:error, changeset} =
               Channels.create_channel(%{workspace_id: workspace.id, name: "general"})

      assert "has already been taken" in errors_on(changeset).name
    end

    test "rejects invalid channel types" do
      {workspace, _owner} = workspace_fixture()

      assert {:error, changeset} =
               Channels.create_channel(%{
                 workspace_id: workspace.id,
                 name: "general",
                 type: "secret"
               })

      assert "is invalid" in errors_on(changeset).type
    end
  end

  describe "join_channel/2" do
    test "adds a user to a channel" do
      {workspace, _owner} = workspace_fixture()
      channel = channel_fixture(workspace)
      user = user_fixture()

      assert {:ok, _member} = Channels.join_channel(channel.id, user.id)
      assert [member] = Channels.list_members(channel.id)
      assert member.user_id == user.id
    end

    test "prevents joining the same channel twice" do
      {workspace, _owner} = workspace_fixture()
      channel = channel_fixture(workspace)
      user = user_fixture()

      assert {:ok, _} = Channels.join_channel(channel.id, user.id)
      assert {:error, changeset} = Channels.join_channel(channel.id, user.id)
      assert Keyword.has_key?(changeset.errors, :channel_id)
    end
  end

  describe "list_channels/1" do
    test "returns channels for the workspace ordered by name" do
      {workspace, _owner} = workspace_fixture()
      _b = channel_fixture(workspace, %{name: "zulu"})
      _a = channel_fixture(workspace, %{name: "alpha"})

      names = workspace.id |> Channels.list_channels() |> Enum.map(& &1.name)
      assert names == ["alpha", "zulu"]
    end
  end
end
