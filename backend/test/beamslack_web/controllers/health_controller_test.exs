defmodule BeamSlackWeb.HealthControllerTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest

  defp health do
    build_conn(:get, "/api/health")
    |> BeamSlackWeb.Router.call(BeamSlackWeb.Router.init([]))
    |> json_response(200)
  end

  test "GET /api/health reports that the API is available" do
    assert %{"status" => "ok"} = health()
  end

  test "it names the node that answered" do
    assert %{"node" => node} = health()
    assert node == to_string(Node.self())
  end

  test "it lists the nodes this one is clustered with" do
    # `nonode@nohost` under test, and the empty list is the honest answer: a node
    # that is not distributed is connected to nothing.
    assert %{"connected_nodes" => connected} = health()
    assert connected == Enum.map(Node.list(), &to_string/1)
  end
end
