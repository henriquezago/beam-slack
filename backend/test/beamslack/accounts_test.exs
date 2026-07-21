use BeamSlack.DataCase

defmodule BeamSlack.AccountsTest do
  use BeamSlack.DataCase

  test "register_user/1" do
    assert BeamSlack.Accounts.register_user(%{name: "John Doe", email: "john.doe@example.com", password: "password"}) == {:ok, %User{id: 1, name: "John Doe", email: "john.doe@example.com"}}
  end

  test "get_user/1" do
    assert BeamSlack.Accounts.get_user(1) == %User{id: 1, name: "John Doe", email: "john.doe@example.com"}
  end

  test "get_user_by_email/1" do
    assert BeamSlack.Accounts.get_user_by_email("john.doe@example.com") == %User{id: 1, name: "John Doe", email: "john.doe@example.com"}
  end

  test "list_users/0" do
    assert BeamSlack.Accounts.list_users() == [%User{id: 1, name: "John Doe", email: "john.doe@example.com"}]
  end

  test "update_user/2" do
    assert BeamSlack.Accounts.update_user(%User{id: 1, name: "John Doe", email: "john.doe@example.com"}, %{name: "Jane Doe"}) == %User{id: 1, name: "Jane Doe", email: "john.doe@example.com"}
  end

  test "delete_user/1" do
    assert BeamSlack.Accounts.delete_user(%User{id: 1, name: "John Doe", email: "john.doe@example.com"}) == {:ok, %User{id: 1, name: "John Doe", email: "john.doe@example.com"}}
  end
end
