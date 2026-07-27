defmodule BeamSlackWeb.SessionController do
  use BeamSlackWeb, :controller

  alias BeamSlack.Accounts
  alias BeamSlackWeb.Auth

  action_fallback BeamSlackWeb.FallbackController

  def create(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate_user(email, password) do
      conn
      |> put_view(json: BeamSlackWeb.UserJSON)
      |> render(:session, user: user, token: Auth.sign(user))
    end
  end

  def create(_conn, _params), do: {:error, :unauthorized}
end
