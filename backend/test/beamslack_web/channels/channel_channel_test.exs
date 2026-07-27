defmodule BeamSlackWeb.ChannelChannelTest do
  @moduledoc """
  Covers the finished plumbing: joining and its authorization.

  The message, presence, and typing handlers are Labs 02, 04, and 05, and their
  tests live in `channel_channel_lab_test.exs`.
  """

  use BeamSlackWeb.ChannelCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlackWeb.ChannelChannel
  alias BeamSlackWeb.UserSocket

  setup do
    user = user_fixture()
    {workspace, _owner} = workspace_fixture(user)

    # `socket/3` is a macro that reads @endpoint, so it has to be called here
    # rather than from a helper in ChannelCase.
    socket = socket(UserSocket, "user_socket:#{user.id}", %{current_user: user})

    %{user: user, workspace: workspace, socket: socket}
  end

  describe "join/3" do
    test "a workspace member joins a public channel", %{
      socket: socket,
      workspace: workspace
    } do
      channel = channel_fixture(workspace, %{name: "general"})

      assert {:ok, reply, joined} =
               subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")

      assert reply == %{channel_id: channel.id, name: "general"}
      assert joined.assigns.channel.id == channel.id
    end

    test "the channel is put on the socket for later handlers", %{
      socket: socket,
      workspace: workspace
    } do
      channel = channel_fixture(workspace)

      {:ok, _reply, joined} = subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")

      assert joined.assigns.channel.workspace_id == workspace.id
      assert joined.assigns.current_user
    end

    test "a channel in another workspace is forbidden", %{socket: socket} do
      {other_workspace, _owner} = workspace_fixture()
      channel = channel_fixture(other_workspace)

      assert {:error, %{reason: "forbidden"}} =
               subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")
    end

    test "a private channel is forbidden to a non-member", %{
      socket: socket,
      workspace: workspace
    } do
      channel = channel_fixture(workspace, %{type: "private"})

      assert {:error, %{reason: "forbidden"}} =
               subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")
    end

    test "a private channel is joinable by its own members", %{
      socket: socket,
      workspace: workspace,
      user: user
    } do
      channel = channel_fixture(workspace, %{type: "private"}, user.id)

      assert {:ok, _reply, _joined} =
               subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")
    end

    test "an unknown channel is not found", %{socket: socket} do
      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, ChannelChannel, "channel:#{Ecto.UUID.generate()}")
    end

    test "a malformed channel id is not found", %{socket: socket} do
      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, ChannelChannel, "channel:not-a-uuid")
    end
  end
end
