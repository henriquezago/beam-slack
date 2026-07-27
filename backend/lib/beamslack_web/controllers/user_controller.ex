defmodule BeamSlackWeb.UserController do
  use BeamSlackWeb, :controller

  alias BeamSlack.Accounts
  alias BeamSlackWeb.Auth

  action_fallback BeamSlackWeb.FallbackController

  @doc """
  Registers a user and returns a token, so a new client is immediately
  authenticated without a second round trip.
  """
  def create(conn, %{"user" => user_params}), do: register(conn, user_params)
  def create(conn, params), do: register(conn, params)

  def me(conn, _params) do
    render(conn, :show, user: conn.assigns.current_user)
  end

  def index(conn, _params) do
    render(conn, :index, users: Accounts.list_users())
  end

  defp register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params) do
      conn
      |> put_status(:created)
      |> render(:session, user: user, token: Auth.sign(user))
    end
  end
end
