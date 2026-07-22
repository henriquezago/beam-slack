defmodule BeamSlack.MessagingTest do
  @moduledoc """
  Tests for the Messaging context.
  """

  use BeamSlack.DataCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Messaging
  alias BeamSlack.Messaging.Message

  setup do
    {workspace, owner} = workspace_fixture()
    channel = channel_fixture(workspace)
    %{workspace: workspace, owner: owner, channel: channel}
  end

  describe "send_message/1" do
    test "persists a message", %{channel: channel, owner: owner} do
      assert {:ok, %Message{} = message} =
               Messaging.send_message(%{
                 channel_id: channel.id,
                 sender_id: owner.id,
                 body: "hello world"
               })

      assert message.body == "hello world"
      assert message.channel_id == channel.id
      assert message.sender_id == owner.id
    end

    test "requires a body", %{channel: channel, owner: owner} do
      assert {:error, changeset} =
               Messaging.send_message(%{channel_id: channel.id, sender_id: owner.id})

      assert "can't be blank" in errors_on(changeset).body
    end
  end

  describe "list_messages/2" do
    test "returns messages oldest-first with sender preloaded", %{
      channel: channel,
      owner: owner
    } do
      {:ok, _first} =
        Messaging.send_message(%{channel_id: channel.id, sender_id: owner.id, body: "first"})

      {:ok, _second} =
        Messaging.send_message(%{channel_id: channel.id, sender_id: owner.id, body: "second"})

      messages = Messaging.list_messages(channel.id)
      assert Enum.map(messages, & &1.body) == ["first", "second"]
      assert [%{sender: sender} | _] = messages
      assert sender.id == owner.id
    end

    test "honors the limit option", %{channel: channel, owner: owner} do
      for body <- ["a", "b", "c"] do
        Messaging.send_message(%{channel_id: channel.id, sender_id: owner.id, body: body})
      end

      assert length(Messaging.list_messages(channel.id, limit: 2)) == 2
    end
  end
end
