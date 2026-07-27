defmodule BeamSlackWeb.UserJSON do
  @moduledoc """
  Renders users. Never renders `password_hash`.
  """

  alias BeamSlack.Accounts.User

  def index(%{users: users}), do: %{data: Enum.map(users, &data/1)}

  def show(%{user: user}), do: %{data: data(user)}

  def session(%{user: user, token: token}) do
    %{data: %{token: token, user: data(user)}}
  end

  @doc """
  The public shape of a user, reused by other views that embed an author.
  """
  def data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      inserted_at: user.inserted_at
    }
  end
end
