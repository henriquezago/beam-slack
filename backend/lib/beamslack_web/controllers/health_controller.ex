defmodule BeamSlackWeb.HealthController do
  use BeamSlackWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
