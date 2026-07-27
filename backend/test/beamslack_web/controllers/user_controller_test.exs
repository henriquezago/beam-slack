defmodule BeamSlackWeb.UserControllerTest do
  use BeamSlackWeb.ConnCase, async: true

  import BeamSlack.Fixtures

  describe "POST /api/users" do
    test "registers a user and returns a token", %{conn: conn} do
      params = %{name: "henrique", email: "henrique@example.com", password: "password123"}

      conn = post(conn, ~p"/api/users", params)

      assert %{"data" => %{"token" => token, "user" => user}} = json_response(conn, 201)
      assert is_binary(token)
      assert user["name"] == "henrique"
      assert user["email"] == "henrique@example.com"
      refute Map.has_key?(user, "password")
      refute Map.has_key?(user, "password_hash")
    end

    test "accepts params nested under a user key", %{conn: conn} do
      params = %{user: %{name: "nested", email: "nested@example.com", password: "password123"}}

      assert %{"data" => %{"user" => user}} =
               json_response(post(conn, ~p"/api/users", params), 201)

      assert user["name"] == "nested"
    end

    test "returns validation errors", %{conn: conn} do
      conn = post(conn, ~p"/api/users", %{name: "x", email: "not-an-email", password: "short"})

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["email"] == ["has invalid format"]
      assert errors["password"] == ["should be at least 8 character(s)"]
    end

    test "rejects a duplicate email", %{conn: conn} do
      existing = user_fixture()

      conn =
        post(conn, ~p"/api/users", %{
          name: "someone-else",
          email: existing.email,
          password: "password123"
        })

      assert %{"errors" => %{"email" => ["has already been taken"]}} = json_response(conn, 422)
    end
  end

  describe "GET /api/me" do
    setup :register_and_log_in_user

    test "returns the authenticated user", %{conn: conn, user: user} do
      assert %{"data" => data} = json_response(get(conn, ~p"/api/me"), 200)
      assert data["id"] == user.id
      assert data["email"] == user.email
    end
  end

  describe "GET /api/users" do
    setup :register_and_log_in_user

    test "lists users", %{conn: conn, user: user} do
      other = user_fixture()

      assert %{"data" => users} = json_response(get(conn, ~p"/api/users"), 200)
      ids = Enum.map(users, & &1["id"])
      assert user.id in ids
      assert other.id in ids
    end

    test "requires authentication", %{conn: _conn} do
      assert json_response(get(build_conn(), ~p"/api/users"), 401)
    end
  end
end
