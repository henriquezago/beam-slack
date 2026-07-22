defmodule BeamSlack.AccountsTest do
  @moduledoc """
  Tests for the Accounts module.
  """

  use BeamSlack.DataCase, async: true
  alias Bcrypt
  alias BeamSlack.Accounts
  alias BeamSlack.Accounts.User

  @valid_attrs %{
    name: "John Doe",
    email: "john.doe@example.com",
    password: "password123"
  }

  defp user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(@valid_attrs)
      |> Accounts.register_user()

    user
  end

  describe "register_user/1" do
    test "creates a user with a hashed password" do
      assert {:ok, %User{} = user} = Accounts.register_user(@valid_attrs)
      assert user.name == "John Doe"
      assert user.email == "john.doe@example.com"
      assert is_binary(user.password_hash)
      assert Bcrypt.verify_pass("password123", user.password_hash)
    end

    test "returns error with invalid data" do
      assert {:error, %Ecto.Changeset{}} = Accounts.register_user(%{})
    end

    test "returns error when password is too short" do
      assert {:error, changeset} =
               Accounts.register_user(Map.put(@valid_attrs, :password, "short"))

      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end

    test "returns error with duplicate email" do
      user_fixture()

      assert {:error, changeset} = Accounts.register_user(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get_user/1" do
    test "returns the user with the given id" do
      user = user_fixture()
      fetched_user = Accounts.get_user(user.id)

      assert fetched_user.id == user.id
      assert fetched_user.name == user.name
      assert fetched_user.email == user.email
    end

    test "returns nil when the user does not exist" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_user_by_email/1" do
    test "returns the user with the given email" do
      user = user_fixture()
      fetched_user = Accounts.get_user_by_email(user.email)

      assert fetched_user.id == user.id
      assert fetched_user.name == user.name
      assert fetched_user.email == user.email
    end

    test "returns nil when the user does not exist" do
      assert Accounts.get_user_by_email("missing@example.com") == nil
    end
  end

  describe "list_users/0" do
    test "returns all users" do
      user = user_fixture()
      [listed_user] = Accounts.list_users()

      assert listed_user.id == user.id
      assert listed_user.name == user.name
      assert listed_user.email == user.email
    end
  end

  describe "update_user/2" do
    test "updates the user" do
      user = user_fixture()

      assert {:ok, updated_user} = Accounts.update_user(user, %{name: "Jane Doe"})
      assert updated_user.name == "Jane Doe"
      assert updated_user.email == user.email
    end

    test "updates the password when given" do
      user = user_fixture()

      assert {:ok, updated_user} =
               Accounts.update_user(user, %{password: "newpassword123"})

      assert Bcrypt.verify_pass("newpassword123", updated_user.password_hash)
      refute Bcrypt.verify_pass("password123", updated_user.password_hash)
    end
  end

  describe "delete_user/1" do
    test "deletes the user" do
      user = user_fixture()

      assert {:ok, deleted_user} = Accounts.delete_user(user)
      assert deleted_user.id == user.id
      assert Accounts.get_user(user.id) == nil
    end
  end
end
