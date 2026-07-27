defmodule BeamSlackWeb.NotificationControllerTest do
  use BeamSlackWeb.ConnCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Messaging
  alias BeamSlack.Notifications

  setup %{conn: conn} do
    alice = user_fixture(%{name: "alice"})
    bob = user_fixture(%{name: "bob"})
    {workspace, _} = workspace_fixture(alice)
    {:ok, _} = BeamSlack.Workspaces.join_workspace(workspace.id, bob.id)
    channel = channel_fixture(workspace, %{}, alice.id)

    {:ok, _message} =
      Messaging.send_message(%{
        channel_id: channel.id,
        sender_id: alice.id,
        body: "hi @bob"
      })

    %{conn: log_in_user(conn, bob), bob: bob, alice: alice, channel: channel}
  end

  test "lists notifications", %{conn: conn} do
    conn = get(conn, ~p"/api/notifications")
    assert %{"data" => [%{"kind" => "mention"}]} = json_response(conn, 200)
  end

  test "reports unread count", %{conn: conn} do
    conn = get(conn, ~p"/api/notifications/unread_count")
    assert %{"data" => %{"count" => 1}} = json_response(conn, 200)
  end

  test "marks one as read", %{conn: conn, bob: bob} do
    [notification] = Notifications.list_for_user(bob.id)

    conn = post(conn, ~p"/api/notifications/#{notification.id}/read")
    assert %{"data" => %{"read_at" => read_at}} = json_response(conn, 200)
    assert read_at
    assert Notifications.unread_count(bob.id) == 0
  end

  test "marks all as read", %{conn: conn, bob: bob} do
    conn = post(conn, ~p"/api/notifications/read_all")
    assert response(conn, 204)
    assert Notifications.unread_count(bob.id) == 0
  end
end
