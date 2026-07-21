defmodule BeamSlackWeb.HealthControllerTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest

  test "GET /api/health reports that the API is available" do
    conn =
      build_conn(:get, "/api/health")
      |> BeamSlackWeb.Router.call(BeamSlackWeb.Router.init([]))

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
