defmodule BeamSlackWeb.ChannelBroadcastTest do
  @moduledoc """
  The specification for Lab 03. See `docs/labs/03-pubsub-architecture.md`.

  Where the broadcast is emitted from, and which process subscribes, is your
  decision. What these tests insist on is the observable consequence: a message
  sent in one channel reaches every subscriber of that channel's topic and nobody
  else.

  Note that the third test subscribes to PubSub directly rather than through a
  socket. That is deliberate: it stands in for the other subscribers Lab 03 asks
  you to plan for, and for a second node in Track 4.

  Run with `mix test.labs`.
  """

  use BeamSlackWeb.ChannelCase, async: true

  @moduletag :lab

  import BeamSlack.Fixtures

  alias BeamSlackWeb.ChannelChannel
  alias BeamSlackWeb.Endpoint
  alias BeamSlackWeb.UserSocket

  setup do
    user = user_fixture()
    {workspace, _owner} = workspace_fixture(user)
    channel = channel_fixture(workspace, %{name: "general"}, user.id)

    socket = socket(UserSocket, "user_socket:#{user.id}", %{current_user: user})
    {:ok, _reply, joined} = subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")

    %{user: user, workspace: workspace, channel: channel, joined: joined}
  end

  describe "fan-out" do
    test "a new message is broadcast on the channel topic", %{joined: joined} do
      ref = push(joined, "new_message", %{"body" => "everyone should see this"})
      assert_reply ref, :ok, _message, 1_000

      assert_broadcast "new_message", %{body: "everyone should see this"}, 1_000
    end

    test "the broadcast payload matches the client's contract", %{
      joined: joined,
      user: user,
      channel: channel
    } do
      ref = push(joined, "new_message", %{"body" => "shape check"})
      assert_reply ref, :ok, _message, 1_000

      assert_broadcast "new_message", payload, 1_000

      for key <- [:id, :channel_id, :sender_id, :body, :inserted_at, :sender] do
        assert Map.has_key?(payload, key),
               "the broadcast payload is missing #{inspect(key)}, so the React client cannot render it"
      end

      assert payload.channel_id == channel.id
      assert payload.sender_id == user.id
      assert payload.sender.name == user.name
    end

    test "a subscriber that is not a socket also receives the message", %{
      joined: joined,
      channel: channel
    } do
      Endpoint.subscribe("channel:#{channel.id}")

      ref = push(joined, "new_message", %{"body" => "for the bystanders too"})
      assert_reply ref, :ok, _message, 1_000

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "new_message",
                       payload: %{body: "for the bystanders too"}
                     },
                     1_000
    end
  end

  describe "isolation" do
    test "a message in one channel is not broadcast on another channel's topic", %{
      joined: joined,
      workspace: workspace
    } do
      other = channel_fixture(workspace, %{name: "random"})
      Endpoint.subscribe("channel:#{other.id}")

      ref = push(joined, "new_message", %{"body" => "meant for general only"})
      assert_reply ref, :ok, _message, 1_000

      refute_receive %Phoenix.Socket.Broadcast{event: "new_message"}, 300
    end

    test "a message is not broadcast on a workspace-wide topic by accident", %{
      joined: joined,
      workspace: workspace
    } do
      # If you decide a workspace topic should exist, it must carry something
      # other than raw message bodies, or every client learns about every private
      # channel it cannot read.
      Endpoint.subscribe("workspace:#{workspace.id}")

      ref = push(joined, "new_message", %{"body" => "secret to general"})
      assert_reply ref, :ok, _message, 1_000

      refute_receive %Phoenix.Socket.Broadcast{
                       event: "new_message",
                       payload: %{body: "secret to general"}
                     },
                     300
    end
  end
end
