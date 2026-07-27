defmodule BeamSlackWeb.Auth do
  @moduledoc """
  Token-based authentication for the JSON API and the socket.

  Tokens are signed with `Phoenix.Token` using the endpoint's secret key base, so
  there is no session table and no server-side state to keep. That is a
  deliberate choice for this stage of the project: authentication state is
  neither durable nor ephemeral runtime state, it is carried by the client.

  Clients send `Authorization: Bearer <token>`. The socket reuses `verify/1`
  with a token passed as a connect param.
  """

  import Plug.Conn

  alias BeamSlack.Accounts
  alias BeamSlack.Accounts.User

  @salt "user auth"
  @max_age 60 * 60 * 24 * 7

  @doc """
  Signs a token identifying `user`.
  """
  @spec sign(%{id: String.t()}) :: String.t()
  def sign(%{id: user_id}) do
    Phoenix.Token.sign(BeamSlackWeb.Endpoint, @salt, user_id)
  end

  @doc """
  Verifies a token and returns the user id it was signed for.
  """
  @spec verify(String.t()) :: {:ok, String.t()} | {:error, :expired | :invalid | :missing}
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(BeamSlackWeb.Endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_token), do: {:error, :missing}

  @doc """
  Verifies a token and loads the user it belongs to.
  """
  @spec verify_user(String.t()) :: {:ok, User.t()} | {:error, term()}
  def verify_user(token) do
    with {:ok, user_id} <- verify(token) do
      case Accounts.get_user(user_id) do
        %User{} = user -> {:ok, user}
        nil -> {:error, :invalid}
      end
    end
  end

  @doc """
  Plug that assigns `:current_user` from the bearer token, or nil when absent or
  invalid. Does not reject the request; pair it with `require_authenticated_user/2`.
  """
  def fetch_current_user(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, user} <- verify_user(token) do
      assign(conn, :current_user, user)
    else
      _ -> assign(conn, :current_user, nil)
    end
  end

  @doc """
  Plug that halts with 401 unless a user was authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.put_view(json: BeamSlackWeb.ErrorJSON)
      |> Phoenix.Controller.render(:"401")
      |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _rest] -> {:ok, String.trim(token)}
      _ -> {:error, :missing}
    end
  end
end
