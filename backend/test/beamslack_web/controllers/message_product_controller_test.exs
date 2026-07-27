defmodule BeamSlackWeb.MessageProductControllerTest do
  use BeamSlackWeb.ConnCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Messaging

  setup %{conn: conn} do
    user = user_fixture(%{name: "alice"})
    other = user_fixture(%{name: "bob"})
    {workspace, _} = workspace_fixture(user)
    {:ok, _} = BeamSlack.Workspaces.join_workspace(workspace.id, other.id)
    channel = channel_fixture(workspace, %{}, user.id)
    {:ok, _} = BeamSlack.Channels.join_channel(channel.id, other.id)

    %{
      conn: log_in_user(conn, user),
      user: user,
      other: other,
      other_conn: log_in_user(build_conn(), other),
      channel: channel
    }
  end

  test "creates a thread reply", %{conn: conn, channel: channel, user: user} do
    {:ok, root} =
      Messaging.send_message(%{
        channel_id: channel.id,
        sender_id: user.id,
        body: "root"
      })

    conn =
      post(conn, ~p"/api/channels/#{channel.id}/messages", %{
        body: "reply",
        thread_root_id: root.id
      })

    assert %{
             "data" => %{
               "body" => "reply",
               "thread_root_id" => root_id,
               "reply_count" => 0
             }
           } = json_response(conn, 201)

    assert root_id == root.id
  end

  test "lists a thread", %{conn: conn, channel: channel, user: user, other: other} do
    {:ok, root} =
      Messaging.send_message(%{
        channel_id: channel.id,
        sender_id: user.id,
        body: "root"
      })

    {:ok, _} =
      Messaging.reply_to_message(%{
        channel_id: channel.id,
        sender_id: other.id,
        body: "reply",
        thread_root_id: root.id
      })

    conn = get(conn, ~p"/api/messages/#{root.id}/thread")
    assert %{"data" => messages} = json_response(conn, 200)
    assert Enum.map(messages, & &1["body"]) == ["root", "reply"]
  end

  test "adds and removes a reaction", %{conn: conn, channel: channel, user: user} do
    {:ok, message} =
      Messaging.send_message(%{
        channel_id: channel.id,
        sender_id: user.id,
        body: "react"
      })

    conn = post(conn, ~p"/api/messages/#{message.id}/reactions", %{emoji: "🎉"})

    assert %{"data" => [%{"emoji" => "🎉", "count" => 1, "reacted" => true}]} =
             json_response(conn, 200)

    conn = delete(conn, ~p"/api/messages/#{message.id}/reactions", %{emoji: "🎉"})
    assert %{"data" => []} = json_response(conn, 200)
  end

  test "message listing includes reaction summary", %{
    conn: conn,
    channel: channel,
    user: user
  } do
    {:ok, message} =
      Messaging.send_message(%{
        channel_id: channel.id,
        sender_id: user.id,
        body: "hi"
      })

    Messaging.add_reaction(message.id, user.id, "❤️")

    conn = get(conn, ~p"/api/channels/#{channel.id}/messages")
    assert %{"data" => [rendered]} = json_response(conn, 200)
    assert [%{"emoji" => "❤️", "reacted" => true}] = rendered["reactions"]
  end
end
