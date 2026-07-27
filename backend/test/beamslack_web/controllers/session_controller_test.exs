defmodule BeamSlackWeb.SessionControllerTest do
  use BeamSlackWeb.ConnCase, async: true

  import BeamSlack.Fixtures

  describe "POST /api/session" do
    test "returns a token for valid credentials", %{conn: conn} do
      user = user_fixture(%{password: "supersecret"})

      conn = post(conn, ~p"/api/session", %{email: user.email, password: "supersecret"})

      assert %{"data" => %{"token" => token, "user" => rendered}} = json_response(conn, 200)
      assert is_binary(token)
      assert rendered["id"] == user.id
      refute Map.has_key?(rendered, "password_hash")
    end

    test "rejects a wrong password", %{conn: conn} do
      user = user_fixture(%{password: "supersecret"})

      conn = post(conn, ~p"/api/session", %{email: user.email, password: "wrong"})

      assert json_response(conn, 401)
    end

    test "rejects an unknown email", %{conn: conn} do
      conn = post(conn, ~p"/api/session", %{email: "nobody@example.com", password: "whatever"})

      assert json_response(conn, 401)
    end

    test "rejects a request with no credentials", %{conn: conn} do
      conn = post(conn, ~p"/api/session", %{})

      assert json_response(conn, 401)
    end
  end

  describe "token authentication" do
    test "a valid token authenticates a protected route", %{conn: conn} do
      user = user_fixture()

      conn = conn |> log_in_user(user) |> get(~p"/api/me")

      assert %{"data" => %{"id" => id}} = json_response(conn, 200)
      assert id == user.id
    end

    test "a missing token is rejected", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/me"), 401)
    end

    test "a garbage token is rejected", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-real-token")
        |> get(~p"/api/me")

      assert json_response(conn, 401)
    end

    test "a token for a deleted user is rejected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:ok, _deleted} = BeamSlack.Accounts.delete_user(user)

      assert json_response(get(conn, ~p"/api/me"), 401)
    end
  end
end
