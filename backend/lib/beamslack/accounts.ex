defmodule BeamSlack.Accounts do
  import Ecto.Query
  alias BeamSlack.Accounts.User
  alias BeamSlack.Repo

  def register_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def get_user(id) do
    User
    |> where(id: ^id)
    |> Repo.one()
  end

  def get_user_by_email(email) do
    User
    |> where(email: ^email)
    |> Repo.one()
  end

  def list_users() do
    User
    |> Repo.all()
  end

  def update_user(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(user) do
    Repo.delete(user)
  end
end
