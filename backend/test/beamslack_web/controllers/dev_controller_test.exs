defmodule BeamSlackWeb.DevControllerTest do
  use BeamSlackWeb.ConnCase, async: false

  alias BeamSlack.Dev.FloodTarget

  describe "GET /dev/faults" do
    test "reports a snapshot and the available faults", %{conn: conn} do
      conn = get(conn, ~p"/dev/faults")

      assert %{"data" => %{"snapshot" => snapshot, "usage" => usage}} = json_response(conn, 200)

      assert snapshot["process_count"] > 0
      assert is_list(snapshot["targets"])
      assert map_size(usage) > 0
    end

    test "renders pids as strings rather than dropping them", %{conn: conn} do
      conn = get(conn, ~p"/dev/faults")

      %{"data" => %{"snapshot" => %{"targets" => targets}}} = json_response(conn, 200)
      repo = Enum.find(targets, &(&1["name"] == "repo"))

      assert repo["pid"] =~ "#PID<"
    end
  end

  describe "POST /dev/faults/kill/:target" do
    test "refuses an unknown target", %{conn: conn} do
      conn = post(conn, ~p"/dev/faults/kill/nonsense")

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
      assert detail =~ "unknown_target"
    end
  end

  describe "flood" do
    test "queues work and reports the queue without messaging the target", %{conn: conn} do
      FloodTarget.drain()

      conn = post(conn, ~p"/dev/faults/flood?count=100")
      assert %{"data" => %{"sent" => 100}} = json_response(conn, 200)

      Process.sleep(50)

      conn = get(conn, ~p"/dev/faults/flood")
      assert %{"data" => %{"mailbox_len" => len}} = json_response(conn, 200)
      assert len > 0

      FloodTarget.drain()
    end
  end
end
