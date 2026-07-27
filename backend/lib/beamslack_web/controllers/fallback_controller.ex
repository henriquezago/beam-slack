defmodule BeamSlackWeb.FallbackController do
  @moduledoc """
  Translates the error tuples returned by the contexts into JSON responses.

  Wired into controllers with `action_fallback BeamSlackWeb.FallbackController`
  so the happy path in each action stays free of error handling.
  """

  use BeamSlackWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: BeamSlackWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :not_found}), do: send_error(conn, :not_found, :"404")
  def call(conn, {:error, :wrong_channel}), do: send_error(conn, :not_found, :"404")
  def call(conn, {:error, :not_a_root}), do: send_error(conn, :unprocessable_entity, :"422")
  def call(conn, {:error, :forbidden}), do: send_error(conn, :forbidden, :"403")
  def call(conn, {:error, :unauthorized}), do: send_error(conn, :unauthorized, :"401")
  def call(conn, {:error, :invalid_credentials}), do: send_error(conn, :unauthorized, :"401")
  def call(conn, nil), do: send_error(conn, :not_found, :"404")

  defp send_error(conn, status, template) do
    conn
    |> put_status(status)
    |> put_view(json: BeamSlackWeb.ErrorJSON)
    |> render(template)
  end
end
