defmodule BeamSlackWeb.UserSocketTest do
  use BeamSlackWeb.ChannelCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlackWeb.Auth
  alias BeamSlackWeb.UserSocket

  describe "connect/3" do
    test "accepts a valid token and assigns the user" do
      user = user_fixture()

      assert {:ok, socket} = connect(UserSocket, %{"token" => Auth.sign(user)})
      assert socket.assigns.current_user.id == user.id
    end

    test "rejects a missing token" do
      assert :error = connect(UserSocket, %{})
    end

    test "rejects a garbage token" do
      assert :error = connect(UserSocket, %{"token" => "not-a-token"})
    end

    test "rejects a token whose user no longer exists" do
      user = user_fixture()
      token = Auth.sign(user)
      {:ok, _deleted} = BeamSlack.Accounts.delete_user(user)

      assert :error = connect(UserSocket, %{"token" => token})
    end
  end

  describe "id/1" do
    test "scopes the connection to the user so it can be disconnected" do
      user = user_fixture()
      {:ok, socket} = connect(UserSocket, %{"token" => Auth.sign(user)})

      assert UserSocket.id(socket) == "user_socket:#{user.id}"
    end
  end
end
