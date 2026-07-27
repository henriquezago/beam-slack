defmodule BeamSlackWeb.ChannelMessageTest do
  @moduledoc """
  The specification for Lab 02. See `docs/labs/02-persist-vs-broadcast.md`.

  Covers what a `"new_message"` push must reply and what must end up in
  PostgreSQL. Whether the broadcast happens before or after the insert is your
  decision; these tests only insist that a reply and a persisted row agree with
  each other, and that a failed send persists nothing.

  Run with `mix test.labs`.
  """

  use BeamSlackWeb.ChannelCase, async: true

  @moduletag :lab

  import BeamSlack.Fixtures

  alias BeamSlack.Messaging
  alias BeamSlackWeb.ChannelChannel
  alias BeamSlackWeb.UserSocket

  setup do
    user = user_fixture()
    {workspace, _owner} = workspace_fixture(user)
    channel = channel_fixture(workspace, %{name: "general"}, user.id)

    socket = socket(UserSocket, "user_socket:#{user.id}", %{current_user: user})
    {:ok, _reply, joined} = subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")

    %{user: user, workspace: workspace, channel: channel, joined: joined}
  end

  describe "new_message" do
    test "replies with the created message", %{joined: joined, user: user, channel: channel} do
      ref = push(joined, "new_message", %{"body" => "hello from the socket"})

      assert_reply ref, :ok, message, 1_000

      assert message.body == "hello from the socket"
      assert message.channel_id == channel.id
      assert message.sender_id == user.id
      assert is_binary(message.id)
      assert message.inserted_at
    end

    test "the reply embeds the sender, so the client can render it immediately", %{
      joined: joined,
      user: user
    } do
      ref = push(joined, "new_message", %{"body" => "who said that"})

      assert_reply ref, :ok, message, 1_000
      assert message.sender.id == user.id
      assert message.sender.name == user.name
    end

    test "the message is persisted", %{joined: joined, channel: channel} do
      ref = push(joined, "new_message", %{"body" => "durable"})
      assert_reply ref, :ok, _message, 1_000

      assert [persisted] = Messaging.list_messages(channel.id)
      assert persisted.body == "durable"
    end

    test "the reply id matches the persisted row", %{joined: joined, channel: channel} do
      ref = push(joined, "new_message", %{"body" => "same row"})
      assert_reply ref, :ok, message, 1_000

      assert [persisted] = Messaging.list_messages(channel.id)

      assert persisted.id == message.id,
             "the client was told about a message that is not the one in the database"
    end

    test "a blank body is rejected and persists nothing", %{joined: joined, channel: channel} do
      ref = push(joined, "new_message", %{"body" => ""})

      assert_reply ref, :error, %{errors: %{body: [_message | _rest]}}, 1_000
      assert Messaging.list_messages(channel.id) == []
    end

    test "a rejected send does not leave a phantom message behind", %{
      joined: joined,
      channel: channel
    } do
      ref = push(joined, "new_message", %{"body" => ""})
      assert_reply ref, :error, _payload, 1_000

      refute_broadcast "new_message", _payload

      assert Messaging.list_messages(channel.id) == []
    end

    test "the channel survives a rejected send", %{joined: joined, channel: channel} do
      ref = push(joined, "new_message", %{"body" => ""})
      assert_reply ref, :error, _payload, 1_000

      ref = push(joined, "new_message", %{"body" => "still here"})
      assert_reply ref, :ok, _message, 1_000

      assert [%{body: "still here"}] = Messaging.list_messages(channel.id)
    end
  end

  describe "authorization" do
    setup %{workspace: workspace, channel: channel} do
      # A workspace member who never joined this channel. They can read it, so
      # they can join the topic, but posting is another matter.
      reader = user_fixture()
      {:ok, _member} = BeamSlack.Workspaces.join_workspace(workspace.id, reader.id)

      socket = socket(UserSocket, "user_socket:#{reader.id}", %{current_user: reader})
      {:ok, _reply, joined} = subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")

      %{reader: reader, reader_socket: joined}
    end

    test "a workspace member who has not joined the channel cannot post", %{
      reader_socket: joined,
      channel: channel
    } do
      ref = push(joined, "new_message", %{"body" => "let me in"})

      assert_reply ref, :error, %{reason: "forbidden"}, 1_000
      assert Messaging.list_messages(channel.id) == []
    end
  end
end
