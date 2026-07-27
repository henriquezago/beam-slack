defmodule BeamSlack.Dev.FaultInjectionTest do
  @moduledoc """
  Tests for the Track 3 harness itself.

  Deliberately narrow. The harness's job is to break things, and a test suite that
  actually exercised that would spend its time killing the application it runs
  inside — `BeamSlack.Supervisor` allows three restarts in five seconds, so a test
  that kills a supervised child four times takes the whole node down and every
  other test with it. So these tests check the plumbing, and the interesting
  behavior is checked by hand against a running server.
  """

  use ExUnit.Case, async: false

  alias BeamSlack.Dev.FaultInjection
  alias BeamSlack.Dev.FloodTarget

  describe "targets/0" do
    test "lists every killable name with its liveness" do
      targets = FaultInjection.targets()

      names = Enum.map(targets, & &1.name)
      assert "repo" in names
      assert "presence" in names
      assert "flood_target" in names

      repo = Enum.find(targets, &(&1.name == "repo"))
      assert is_pid(repo.pid)
    end

    test "reports processes that do not exist as nil rather than failing" do
      targets = FaultInjection.targets()
      registry = Enum.find(targets, &(&1.name == "channel_registry"))

      # Lab 01's registry is absent until the learner adds it to the tree.
      assert registry
      assert is_nil(registry.pid) or is_pid(registry.pid)
    end
  end

  describe "kill/2" do
    test "refuses an unknown target" do
      assert {:error, :unknown_target} = FaultInjection.kill("not_a_process")
    end
  end

  describe "flood/2" do
    setup do
      # Whatever a previous test left queued would otherwise be counted here.
      FloodTarget.drain()
      Process.sleep(50)
      :ok
    end

    test "queues messages the target cannot keep up with" do
      assert {:ok, %{sent: 200}} = FaultInjection.flood(200)

      # No synchronization with the target at all: send/2 returned immediately and
      # the queue is observable from outside while the target is still busy.
      Process.sleep(100)
      assert %{mailbox_len: len} = FloodTarget.observe()
      assert len > 0

      FloodTarget.drain()
    end

    test "observe/0 answers while the target is saturated" do
      {:ok, _result} = FaultInjection.flood(500)

      # stats/0 is a call and goes to the back of the same queue; observe/0 asks
      # the runtime instead of the process. Only one of them can answer now.
      assert %{mailbox_len: _len} = FloodTarget.observe()
      assert {:error, :timeout} = FloodTarget.stats(200)

      FloodTarget.drain()
    end

    test "refuses a target that is not running" do
      assert {:error, :not_running} = FaultInjection.flood(1, target: NotAProcess)
    end
  end

  describe "snapshot/0" do
    test "reports VM counters and every target's mailbox" do
      snapshot = FaultInjection.snapshot()

      assert snapshot.process_count > 0
      assert snapshot.memory_kb > 0
      assert is_list(snapshot.targets)
      assert Enum.all?(snapshot.targets, &Map.has_key?(&1, :mailbox_len))
    end
  end
end
