defmodule BeamSlackWeb.MessageControllerTest do
  use BeamSlackWeb.ConnCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Messaging

  setup :register_and_log_in_user

  setup %{user: user} do
    {workspace, _owner} = workspace_fixture(user)
    channel = channel_fixture(workspace, %{}, user.id)
    %{workspace: workspace, channel: channel}
  end

  describe "POST /api/channels/:channel_id/messages" do
    test "persists a message and embeds the sender", %{
      conn: conn,
      channel: channel,
      user: user
    } do
      conn = post(conn, ~p"/api/channels/#{channel.id}/messages", %{body: "hello beam"})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["body"] == "hello beam"
      assert data["sender_id"] == user.id
      assert data["sender"]["id"] == user.id
      assert [%{body: "hello beam"}] = Messaging.list_messages(channel.id)
    end

    test "requires a body", %{conn: conn, channel: channel} do
      conn = post(conn, ~p"/api/channels/#{channel.id}/messages", %{})

      assert %{"errors" => %{"body" => ["can't be blank"]}} = json_response(conn, 422)
    end

    test "requires channel membership, not just workspace membership", %{
      conn: conn,
      workspace: workspace
    } do
      other_channel = channel_fixture(workspace)

      conn = post(conn, ~p"/api/channels/#{other_channel.id}/messages", %{body: "hi"})

      assert json_response(conn, 403)
    end

    test "forbids posting to another workspace's channel", %{conn: conn} do
      {other_workspace, _owner} = workspace_fixture()
      other_channel = channel_fixture(other_workspace)

      conn = post(conn, ~p"/api/channels/#{other_channel.id}/messages", %{body: "hi"})

      assert json_response(conn, 403)
    end

    test "requires authentication", %{channel: channel} do
      conn = post(build_conn(), ~p"/api/channels/#{channel.id}/messages", %{body: "hi"})

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/channels/:channel_id/messages" do
    test "returns history oldest-first", %{conn: conn, channel: channel, user: user} do
      for body <- ["one", "two", "three"] do
        {:ok, _message} =
          Messaging.send_message(%{channel_id: channel.id, sender_id: user.id, body: body})
      end

      assert %{"data" => messages} =
               json_response(get(conn, ~p"/api/channels/#{channel.id}/messages"), 200)

      assert Enum.map(messages, & &1["body"]) == ["one", "two", "three"]
    end

    test "a limit returns the most recent messages, still oldest-first", %{
      conn: conn,
      channel: channel,
      user: user
    } do
      for body <- ["one", "two", "three"] do
        {:ok, _message} =
          Messaging.send_message(%{channel_id: channel.id, sender_id: user.id, body: body})
      end

      assert %{"data" => messages} =
               json_response(get(conn, ~p"/api/channels/#{channel.id}/messages?limit=2"), 200)

      assert Enum.map(messages, & &1["body"]) == ["two", "three"]
    end

    test "ignores a nonsense limit", %{conn: conn, channel: channel} do
      assert %{"data" => []} =
               json_response(
                 get(conn, ~p"/api/channels/#{channel.id}/messages?limit=banana"),
                 200
               )
    end

    test "reading only requires workspace membership", %{conn: conn, workspace: workspace} do
      other_channel = channel_fixture(workspace)

      assert %{"data" => []} =
               json_response(get(conn, ~p"/api/channels/#{other_channel.id}/messages"), 200)
    end

    test "forbids reading another workspace's channel", %{conn: conn} do
      {other_workspace, _owner} = workspace_fixture()
      other_channel = channel_fixture(other_workspace)

      assert json_response(get(conn, ~p"/api/channels/#{other_channel.id}/messages"), 403)
    end
  end
end
