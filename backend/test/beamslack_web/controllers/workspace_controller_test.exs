defmodule BeamSlackWeb.WorkspaceControllerTest do
  use BeamSlackWeb.ConnCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Workspaces

  setup :register_and_log_in_user

  describe "POST /api/workspaces" do
    test "creates a workspace owned by the current user", %{conn: conn, user: user} do
      conn = post(conn, ~p"/api/workspaces", %{name: "beam-crew"})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "beam-crew"
      assert data["owner_id"] == user.id
      assert Workspaces.member?(data["id"], user.id)
    end

    test "returns validation errors", %{conn: conn} do
      assert %{"errors" => errors} = json_response(post(conn, ~p"/api/workspaces", %{}), 422)
      assert errors["name"] == ["can't be blank"]
    end
  end

  describe "GET /api/workspaces" do
    test "lists only the workspaces the user belongs to", %{conn: conn, user: user} do
      {mine, _owner} = workspace_fixture(user)
      {theirs, _other_owner} = workspace_fixture()

      assert %{"data" => workspaces} = json_response(get(conn, ~p"/api/workspaces"), 200)
      ids = Enum.map(workspaces, & &1["id"])
      assert mine.id in ids
      refute theirs.id in ids
    end
  end

  describe "GET /api/workspaces/:id" do
    test "returns a workspace the user belongs to", %{conn: conn, user: user} do
      {workspace, _owner} = workspace_fixture(user)

      assert %{"data" => data} =
               json_response(get(conn, ~p"/api/workspaces/#{workspace.id}"), 200)

      assert data["id"] == workspace.id
    end

    test "forbids a workspace the user does not belong to", %{conn: conn} do
      {workspace, _owner} = workspace_fixture()

      assert json_response(get(conn, ~p"/api/workspaces/#{workspace.id}"), 403)
    end

    test "returns 404 for an unknown workspace", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/workspaces/#{Ecto.UUID.generate()}"), 404)
    end

    test "returns 404 for a malformed id", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/workspaces/not-a-uuid"), 404)
    end
  end

  describe "POST /api/workspaces/:id/join" do
    test "joins a workspace as a member", %{conn: conn, user: user} do
      {workspace, _owner} = workspace_fixture()

      conn = post(conn, ~p"/api/workspaces/#{workspace.id}/join")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["role"] == "member"
      assert data["user_id"] == user.id
      assert Workspaces.member?(workspace.id, user.id)
    end

    test "is idempotent", %{conn: conn, user: user} do
      {workspace, _owner} = workspace_fixture(user)

      assert json_response(post(conn, ~p"/api/workspaces/#{workspace.id}/join"), 200)

      assert %{"data" => data} =
               json_response(post(conn, ~p"/api/workspaces/#{workspace.id}/join"), 200)

      assert data["role"] == "owner"
      assert length(Workspaces.list_members(workspace.id)) == 1
    end
  end

  describe "GET /api/workspaces/:id/members" do
    test "lists members with their users", %{conn: conn, user: user} do
      {workspace, _owner} = workspace_fixture(user)
      other = user_fixture()
      {:ok, _member} = Workspaces.join_workspace(workspace.id, other.id)

      assert %{"data" => members} =
               json_response(get(conn, ~p"/api/workspaces/#{workspace.id}/members"), 200)

      assert length(members) == 2
      assert Enum.all?(members, &is_map(&1["user"]))
      assert other.id in Enum.map(members, & &1["user_id"])
    end

    test "forbids non-members", %{conn: conn} do
      {workspace, _owner} = workspace_fixture()

      assert json_response(get(conn, ~p"/api/workspaces/#{workspace.id}/members"), 403)
    end
  end
end
