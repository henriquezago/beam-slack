defmodule BeamSlackWeb.ChannelControllerTest do
  use BeamSlackWeb.ConnCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Channels

  setup :register_and_log_in_user

  setup %{user: user} do
    {workspace, _owner} = workspace_fixture(user)
    %{workspace: workspace}
  end

  describe "POST /api/workspaces/:workspace_id/channels" do
    test "creates a channel and joins the creator", %{
      conn: conn,
      workspace: workspace,
      user: user
    } do
      conn = post(conn, ~p"/api/workspaces/#{workspace.id}/channels", %{name: "general"})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "general"
      assert data["type"] == "public"
      assert data["workspace_id"] == workspace.id
      assert Channels.member?(data["id"], user.id)
    end

    test "creates a private channel when asked", %{conn: conn, workspace: workspace} do
      conn =
        post(conn, ~p"/api/workspaces/#{workspace.id}/channels", %{
          name: "secrets",
          type: "private"
        })

      assert %{"data" => %{"type" => "private"}} = json_response(conn, 201)
    end

    test "rejects an invalid type", %{conn: conn, workspace: workspace} do
      conn =
        post(conn, ~p"/api/workspaces/#{workspace.id}/channels", %{name: "x", type: "broadcast"})

      assert %{"errors" => %{"type" => ["is invalid"]}} = json_response(conn, 422)
    end

    test "rejects a duplicate name in the same workspace", %{conn: conn, workspace: workspace} do
      _existing = channel_fixture(workspace, %{name: "general"})

      conn = post(conn, ~p"/api/workspaces/#{workspace.id}/channels", %{name: "general"})

      assert %{"errors" => %{"name" => ["has already been taken"]}} = json_response(conn, 422)
    end

    test "forbids creating in a workspace the user does not belong to", %{conn: conn} do
      {other_workspace, _owner} = workspace_fixture()

      conn = post(conn, ~p"/api/workspaces/#{other_workspace.id}/channels", %{name: "general"})

      assert json_response(conn, 403)
    end
  end

  describe "GET /api/workspaces/:workspace_id/channels" do
    test "lists the workspace channels", %{conn: conn, workspace: workspace} do
      a = channel_fixture(workspace, %{name: "aaa"})
      b = channel_fixture(workspace, %{name: "bbb"})

      assert %{"data" => channels} =
               json_response(get(conn, ~p"/api/workspaces/#{workspace.id}/channels"), 200)

      assert Enum.map(channels, & &1["id"]) == [a.id, b.id]
    end

    test "forbids non-members", %{conn: conn} do
      {other_workspace, _owner} = workspace_fixture()

      assert json_response(get(conn, ~p"/api/workspaces/#{other_workspace.id}/channels"), 403)
    end
  end

  describe "GET /api/channels/:id" do
    test "returns a public channel to a workspace member", %{conn: conn, workspace: workspace} do
      channel = channel_fixture(workspace)

      assert %{"data" => data} = json_response(get(conn, ~p"/api/channels/#{channel.id}"), 200)
      assert data["id"] == channel.id
    end

    test "hides a private channel from a non-member of that channel", %{
      conn: conn,
      workspace: workspace
    } do
      channel = channel_fixture(workspace, %{type: "private"})

      assert json_response(get(conn, ~p"/api/channels/#{channel.id}"), 403)
    end

    test "shows a private channel to its members", %{
      conn: conn,
      workspace: workspace,
      user: user
    } do
      channel = channel_fixture(workspace, %{type: "private"}, user.id)

      assert %{"data" => data} = json_response(get(conn, ~p"/api/channels/#{channel.id}"), 200)
      assert data["id"] == channel.id
    end

    test "returns 404 for an unknown channel", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/channels/#{Ecto.UUID.generate()}"), 404)
    end
  end

  describe "POST /api/channels/:id/join" do
    test "joins a public channel", %{conn: conn, workspace: workspace, user: user} do
      channel = channel_fixture(workspace)

      assert %{"data" => data} =
               json_response(post(conn, ~p"/api/channels/#{channel.id}/join"), 200)

      assert data["user_id"] == user.id
      assert Channels.member?(channel.id, user.id)
    end

    test "is idempotent", %{conn: conn, workspace: workspace, user: user} do
      channel = channel_fixture(workspace, %{}, user.id)

      assert json_response(post(conn, ~p"/api/channels/#{channel.id}/join"), 200)
      assert length(Channels.list_members(channel.id)) == 1
    end

    test "refuses to self-join a private channel", %{conn: conn, workspace: workspace} do
      channel = channel_fixture(workspace, %{type: "private"})

      assert json_response(post(conn, ~p"/api/channels/#{channel.id}/join"), 403)
    end

    test "refuses a channel in another workspace", %{conn: conn} do
      {other_workspace, _owner} = workspace_fixture()
      channel = channel_fixture(other_workspace)

      assert json_response(post(conn, ~p"/api/channels/#{channel.id}/join"), 403)
    end
  end

  describe "GET /api/channels/:id/members" do
    test "lists members with their users", %{conn: conn, workspace: workspace, user: user} do
      channel = channel_fixture(workspace, %{}, user.id)

      assert %{"data" => [member]} =
               json_response(get(conn, ~p"/api/channels/#{channel.id}/members"), 200)

      assert member["user"]["id"] == user.id
    end
  end
end
