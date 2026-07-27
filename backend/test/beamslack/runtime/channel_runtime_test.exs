defmodule BeamSlack.Runtime.ChannelRuntimeTest do
  @moduledoc """
  The specification for Lab 01. See `docs/labs/01-channel-runtime.md`.

  These tests exercise the public API only. They deliberately do not assert
  anything about the Registry key shape, the restart strategy, how idle shutdown
  is triggered, or where the subtree sits, because those are your decisions. If a
  test fails, the contract is broken; if a test passes for the wrong reason, the
  brief's failure questions are there to catch you.

  No database, no sandbox, `async: true`. A runtime that needs `Repo` to answer a
  question is a runtime holding the wrong state.

  Until the lab is implemented, compiling this file warns that a pattern in
  `start!/2` "will never match". That is correct and temporary: every function in
  the skeleton only raises, so the compiler infers `none()` as its return type.
  The warning disappears once `get_or_start/2` returns something.
  """

  use ExUnit.Case, async: true

  @moduletag :lab

  alias BeamSlack.Runtime.ChannelRuntime

  @registry BeamSlack.Runtime.ChannelRegistry
  @supervisor BeamSlack.Runtime.ChannelSupervisor

  setup do
    channel_id = unique_channel_id()
    on_exit(fn -> cleanup(channel_id) end)

    %{channel_id: channel_id, user: unique_user_id()}
  end

  describe "supervision tree" do
    test "the channel registry is running" do
      assert is_pid(Process.whereis(@registry)),
             "#{inspect(@registry)} is not running. Add it to the supervision tree."
    end

    test "the channel supervisor is running" do
      assert is_pid(Process.whereis(@supervisor)),
             "#{inspect(@supervisor)} is not running. Add it to the supervision tree."
    end

    test "a started runtime is supervised by the channel supervisor", %{channel_id: channel_id} do
      pid = start!(channel_id)

      supervised =
        @supervisor
        |> DynamicSupervisor.which_children()
        |> Enum.map(fn {_id, child, _type, _modules} -> child end)

      assert pid in supervised,
             "the runtime is alive but not a child of #{inspect(@supervisor)}"
    end

    test "the runtime is discoverable through the registry", %{channel_id: channel_id} do
      pid = start!(channel_id)
      registered = Registry.select(@registry, [{{:_, :"$1", :_}, [], [:"$1"]}])

      assert pid in registered,
             "the runtime is not registered in #{inspect(@registry)}, so nothing can find it"
    end
  end

  describe "get_or_start/2" do
    test "starts a runtime and returns its pid", %{channel_id: channel_id} do
      pid = start!(channel_id)

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns the same runtime on a second call", %{channel_id: channel_id} do
      pid = start!(channel_id)

      assert ChannelRuntime.get_or_start(channel_id) == {:ok, pid}
    end

    test "different channels get different runtimes", %{channel_id: channel_id} do
      other_id = unique_channel_id()
      on_exit(fn -> cleanup(other_id) end)

      refute start!(channel_id) == start!(other_id)
    end

    test "agrees with whereis/1", %{channel_id: channel_id} do
      assert ChannelRuntime.whereis(channel_id) == start!(channel_id)
    end
  end

  describe "concurrent starts" do
    test "fifty simultaneous callers get one runtime", %{channel_id: channel_id} do
      parent = self()

      tasks =
        for _index <- 1..50 do
          Task.async(fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> ChannelRuntime.get_or_start(channel_id)
            after
              5_000 -> {:error, :never_signalled}
            end
          end)
        end

      # Park every task on the same signal first, so they collide on purpose
      # rather than politely queueing behind each other.
      for _task <- tasks, do: assert_receive({:ready, _pid}, 5_000)
      for task <- tasks, do: send(task.pid, :go)

      results = Task.await_many(tasks, 10_000)
      failures = Enum.reject(results, &match?({:ok, pid} when is_pid(pid), &1))

      assert failures == [], "some callers did not get {:ok, pid}: #{inspect(failures)}"

      pids = Enum.map(results, fn {:ok, pid} -> pid end) |> Enum.uniq()

      assert length(pids) == 1,
             "#{length(pids)} distinct runtimes were started for one channel"

      assert ChannelRuntime.whereis(channel_id) == hd(pids)
    end
  end

  describe "whereis/1" do
    test "returns nil when no runtime is running", %{channel_id: channel_id} do
      assert ChannelRuntime.whereis(channel_id) == nil
    end

    test "does not start a runtime", %{channel_id: channel_id} do
      assert ChannelRuntime.whereis(channel_id) == nil
      assert ChannelRuntime.whereis(channel_id) == nil
    end
  end

  describe "join/2 and leave/2" do
    test "join starts the runtime implicitly", %{channel_id: channel_id, user: user} do
      assert ChannelRuntime.whereis(channel_id) == nil

      join!(channel_id, user)

      assert is_pid(ChannelRuntime.whereis(channel_id))
    end

    test "connected users reflect joins", %{channel_id: channel_id, user: user} do
      other = unique_user_id()

      join!(channel_id, user)
      join!(channel_id, other)

      assert Enum.sort(ChannelRuntime.connected_users(channel_id)) == Enum.sort([user, other])
    end

    test "joining twice counts once", %{channel_id: channel_id, user: user} do
      join!(channel_id, user)
      join!(channel_id, user)

      assert ChannelRuntime.connected_users(channel_id) == [user]
    end

    test "leave removes a user", %{channel_id: channel_id, user: user} do
      join!(channel_id, user)

      assert ChannelRuntime.leave(channel_id, user) == :ok
      assert ChannelRuntime.connected_users(channel_id) == []
    end

    test "leaving twice is harmless", %{channel_id: channel_id, user: user} do
      join!(channel_id, user)

      assert ChannelRuntime.leave(channel_id, user) == :ok
      assert ChannelRuntime.leave(channel_id, user) == :ok
    end

    test "leave on a channel with no runtime does not start one", %{
      channel_id: channel_id,
      user: user
    } do
      assert ChannelRuntime.leave(channel_id, user) == {:error, :not_running}
      assert ChannelRuntime.whereis(channel_id) == nil
    end
  end

  describe "connected_users/1" do
    test "returns an empty list for a channel with no runtime", %{channel_id: channel_id} do
      assert ChannelRuntime.connected_users(channel_id) == []
    end

    test "does not start a runtime", %{channel_id: channel_id} do
      assert ChannelRuntime.connected_users(channel_id) == []
      assert ChannelRuntime.whereis(channel_id) == nil
    end
  end

  describe "stop/1" do
    test "terminates the runtime", %{channel_id: channel_id} do
      pid = start!(channel_id)
      ref = Process.monitor(pid)

      assert ChannelRuntime.stop(channel_id) == :ok
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
      refute Process.alive?(pid)
    end

    test "the runtime stays stopped", %{channel_id: channel_id} do
      pid = start!(channel_id)
      ref = Process.monitor(pid)

      assert ChannelRuntime.stop(channel_id) == :ok
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

      assert ChannelRuntime.whereis(channel_id) == nil,
             "something restarted the runtime after an intentional stop"
    end

    test "is idempotent on a channel with no runtime", %{channel_id: channel_id} do
      assert ChannelRuntime.stop(channel_id) == :ok
      assert ChannelRuntime.stop(channel_id) == :ok
    end
  end

  describe "crashes" do
    test "runtime state does not survive a crash", %{channel_id: channel_id, user: user} do
      join!(channel_id, user)
      pid = ChannelRuntime.whereis(channel_id)

      assert ChannelRuntime.connected_users(channel_id) == [user]

      kill_and_await(pid)

      # Whether the supervisor already restarted it or get_or_start/2 starts a
      # fresh one, the caller must end up with a working runtime holding none of
      # the previous state. Supervisors restore processes, not memory.
      assert is_pid(start!(channel_id))
      assert ChannelRuntime.connected_users(channel_id) == []
    end

    test "one runtime crashing does not disturb another", %{channel_id: channel_id, user: user} do
      other_id = unique_channel_id()
      on_exit(fn -> cleanup(other_id) end)

      join!(channel_id, user)
      join!(other_id, user)

      survivor = ChannelRuntime.whereis(other_id)
      kill_and_await(ChannelRuntime.whereis(channel_id))

      assert Process.alive?(survivor)
      assert ChannelRuntime.connected_users(other_id) == [user]
    end
  end

  describe "idle shutdown" do
    test "an empty runtime shuts itself down", %{channel_id: channel_id} do
      pid = start!(channel_id, idle_timeout: 50)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    end

    test "shutting down when idle is not a crash", %{channel_id: channel_id} do
      pid = start!(channel_id, idle_timeout: 50)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 1_000

      assert reason in [:normal, :shutdown],
             """
             the runtime exited with #{inspect(reason)}, which a supervisor treats as \
             abnormal. Under a restarting child spec that is an idle-shutdown loop.
             """
    end

    test "a runtime with someone connected stays up", %{channel_id: channel_id, user: user} do
      pid = start!(channel_id, idle_timeout: 50)
      join!(channel_id, user)
      ref = Process.monitor(pid)

      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 300
      assert ChannelRuntime.connected_users(channel_id) == [user]
    end

    test "a runtime shuts down after the last user leaves", %{channel_id: channel_id, user: user} do
      pid = start!(channel_id, idle_timeout: 50)
      join!(channel_id, user)
      ref = Process.monitor(pid)

      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 200

      assert ChannelRuntime.leave(channel_id, user) == :ok
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    end
  end

  defp start!(channel_id, opts \\ []) do
    case ChannelRuntime.get_or_start(channel_id, opts) do
      {:ok, pid} -> pid
      other -> flunk("get_or_start/2 returned #{inspect(other)}, expected {:ok, pid}")
    end
  end

  defp join!(channel_id, user) do
    assert ChannelRuntime.join(channel_id, user) == :ok
  end

  defp kill_and_await(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1_000
  end

  defp cleanup(channel_id) do
    # Best effort: every function raises until the lab is implemented, and a
    # raise here would bury the real failure.
    ChannelRuntime.stop(channel_id)
  rescue
    _error -> :ok
  end

  defp unique_channel_id, do: "channel-#{System.unique_integer([:positive])}"
  defp unique_user_id, do: "user-#{System.unique_integer([:positive])}"
end
