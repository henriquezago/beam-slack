defmodule BeamSlack.MessagingProductTest do
  @moduledoc """
  Track 5 coverage: threads, reactions, and mentions.
  """

  use BeamSlack.DataCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Messaging
  alias BeamSlack.Notifications

  setup do
    alice = user_fixture(%{name: "alice"})
    bob = user_fixture(%{name: "bob"})
    {workspace, _owner} = workspace_fixture(alice)
    {:ok, _} = BeamSlack.Workspaces.join_workspace(workspace.id, bob.id)
    channel = channel_fixture(workspace, %{}, alice.id)
    {:ok, _} = BeamSlack.Channels.join_channel(channel.id, bob.id)

    %{alice: alice, bob: bob, channel: channel}
  end

  describe "threads" do
    test "replies bump the root's reply_count", %{alice: alice, bob: bob, channel: channel} do
      {:ok, root} =
        Messaging.send_message(%{
          channel_id: channel.id,
          sender_id: alice.id,
          body: "thread start"
        })

      {:ok, reply} =
        Messaging.reply_to_message(%{
          channel_id: channel.id,
          sender_id: bob.id,
          body: "a reply",
          thread_root_id: root.id
        })

      assert reply.thread_root_id == root.id
      assert Messaging.get_message(root.id).reply_count == 1
      assert length(Messaging.list_thread_replies(root.id)) == 1
      assert Messaging.list_messages(channel.id) |> Enum.map(& &1.id) == [root.id]
    end

    test "thread replies notify the root author", %{alice: alice, bob: bob, channel: channel} do
      {:ok, root} =
        Messaging.send_message(%{
          channel_id: channel.id,
          sender_id: alice.id,
          body: "please reply"
        })

      {:ok, _reply} =
        Messaging.reply_to_message(%{
          channel_id: channel.id,
          sender_id: bob.id,
          body: "here",
          thread_root_id: root.id
        })

      assert Notifications.unread_count(alice.id) == 1
      assert [%{kind: "thread_reply"}] = Notifications.list_for_user(alice.id)
    end
  end

  describe "reactions" do
    test "are unique per user and emoji", %{alice: alice, channel: channel} do
      {:ok, message} =
        Messaging.send_message(%{
          channel_id: channel.id,
          sender_id: alice.id,
          body: "react to me"
        })

      assert {:ok, _} = Messaging.add_reaction(message.id, alice.id, "👍")
      assert {:ok, _} = Messaging.add_reaction(message.id, alice.id, "👍")

      summary = Messaging.reaction_summary(message.id, alice.id)
      assert [%{emoji: "👍", count: 1, reacted: true}] = summary
    end

    test "removing is idempotent", %{alice: alice, channel: channel} do
      {:ok, message} =
        Messaging.send_message(%{
          channel_id: channel.id,
          sender_id: alice.id,
          body: "bye"
        })

      Messaging.add_reaction(message.id, alice.id, "🔥")
      assert :ok = Messaging.remove_reaction(message.id, alice.id, "🔥")
      assert :ok = Messaging.remove_reaction(message.id, alice.id, "🔥")
      assert Messaging.reaction_summary(message.id) == []
    end
  end

  describe "mentions" do
    test "create a notification for the mentioned user", %{
      alice: alice,
      bob: bob,
      channel: channel
    } do
      {:ok, _message} =
        Messaging.send_message(%{
          channel_id: channel.id,
          sender_id: alice.id,
          body: "hey @bob look at this"
        })

      assert Notifications.unread_count(bob.id) == 1
      assert [%{kind: "mention"}] = Notifications.list_for_user(bob.id)
      assert Notifications.unread_count(alice.id) == 0
    end

    test "does not notify the sender for a self-mention", %{alice: alice, channel: channel} do
      {:ok, _message} =
        Messaging.send_message(%{
          channel_id: channel.id,
          sender_id: alice.id,
          body: "talking to @alice"
        })

      assert Notifications.unread_count(alice.id) == 0
    end
  end
end
