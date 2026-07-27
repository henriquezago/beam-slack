defmodule BeamSlack.Runtime.WatcherTest do
  @moduledoc """
  The specification for Lab 06. See `docs/labs/06-monitors-and-links.md`.

  These tests only use the public API and the observable consequence of a death.
  They never assert that you called `Process.monitor/1`, because the point is not
  the function call, it is that the watcher survives what it watches.

  `async: false`, because `BeamSlack.Runtime.Watcher` is a single named process
  and these tests kill things.

  Until the lab is implemented, compiling this file warns about clauses that will
  never match, for the same reason as Lab 01's suite: a function that only raises
  is inferred as returning `none()`.

  Run with `mix test.labs`.
  """

  use ExUnit.Case, async: false

  @moduletag :lab

  alias BeamSlack.Runtime.Watcher

  setup do
    assert is_pid(Process.whereis(Watcher)),
           "BeamSlack.Runtime.Watcher is not running. Add it to the supervision tree."

    Watcher.subscribe(self())

    on_exit(fn ->
      for {pid, _meta} <- safe_watched(), do: Watcher.unwatch(pid)
    end)

    :ok
  end

  describe "watching" do
    test "a watched process appears in watched/0" do
      pid = spawn_idle()
      :ok = Watcher.watch(pid, :some_meta)

      assert {^pid, :some_meta} = find_watched(pid)
    end

    test "the subscriber is notified when a watched process exits normally" do
      pid = spawn(fn -> :ok end)
      :ok = Watcher.watch(pid, :normal_exit)

      assert_receive {:process_down, ^pid, :normal_exit, :normal}, 1_000
    end

    test "the notification carries the exit reason" do
      pid = spawn_idle()
      :ok = Watcher.watch(pid, :crashed)

      Process.exit(pid, :kill)

      assert_receive {:process_down, ^pid, :crashed, :killed}, 1_000
    end

    test "a crashing process reports its exception, not just that it died" do
      pid = spawn(fn -> receive do: (:go -> raise "boom") end)
      :ok = Watcher.watch(pid, :raised)

      send(pid, :go)

      assert_receive {:process_down, ^pid, :raised, reason}, 1_000
      assert match?({%RuntimeError{}, _stacktrace}, reason)
    end

    test "a dead process is watched anyway, and reported immediately" do
      pid = spawn(fn -> :ok end)
      # Make sure it is gone before we ask.
      wait_until_dead(pid)

      :ok = Watcher.watch(pid, :already_dead)

      assert_receive {:process_down, ^pid, :already_dead, _reason}, 1_000
    end

    test "a dead process does not stay in watched/0" do
      pid = spawn_idle()
      :ok = Watcher.watch(pid, :transient)
      Process.exit(pid, :kill)

      assert_receive {:process_down, ^pid, :transient, _reason}, 1_000

      refute find_watched(pid),
             "the watcher reported the death but kept the entry, so watched/0 grows forever"
    end
  end

  describe "surviving what it watches" do
    test "the watcher outlives a killed process" do
      watcher = Process.whereis(Watcher)

      pid = spawn_idle()
      :ok = Watcher.watch(pid, nil)
      Process.exit(pid, :kill)

      assert_receive {:process_down, ^pid, nil, _reason}, 1_000

      assert Process.alive?(watcher),
             "watching killed the watcher, which means it is linked and not monitoring"

      assert Process.whereis(Watcher) == watcher,
             "the watcher died and was restarted, so every other watch was lost too"
    end

    test "the watcher outlives fifty simultaneous deaths" do
      watcher = Process.whereis(Watcher)

      pids = for _each <- 1..50, do: spawn_idle()
      for pid <- pids, do: Watcher.watch(pid, :bulk)
      for pid <- pids, do: Process.exit(pid, :kill)

      for pid <- pids do
        assert_receive {:process_down, ^pid, :bulk, _reason}, 2_000
      end

      assert Process.whereis(Watcher) == watcher
    end

    test "killing the watcher does not kill what it watches" do
      pid = spawn_idle()
      :ok = Watcher.watch(pid, nil)

      watcher = Process.whereis(Watcher)
      Process.exit(watcher, :kill)

      # Give the supervisor a moment to put a new one back.
      Process.sleep(200)

      assert Process.alive?(pid),
             "the watched process died with the watcher, so the link points both ways"

      assert is_pid(Process.whereis(Watcher)), "the watcher was not restarted"
    end
  end

  describe "unwatch/1" do
    test "no notification arrives after unwatching" do
      pid = spawn_idle()
      :ok = Watcher.watch(pid, :cancelled)
      :ok = Watcher.unwatch(pid)

      Process.exit(pid, :kill)

      refute_receive {:process_down, ^pid, _meta, _reason}, 300
    end

    test "unwatching a process that is already dying suppresses the notification" do
      # The race the :flush option to Process.demonitor/2 exists for: the process
      # dies and the :DOWN is already in the watcher's mailbox when unwatch/1 is
      # called. A demonitor without :flush leaves it there to be delivered.
      pid = spawn_idle()
      :ok = Watcher.watch(pid, :racy)

      Process.exit(pid, :kill)
      :ok = Watcher.unwatch(pid)

      refute_receive {:process_down, ^pid, :racy, _reason}, 300
    end

    test "unwatching something that was never watched is fine" do
      assert :ok = Watcher.unwatch(spawn_idle())
    end
  end

  describe "several watches" do
    test "each watched process is reported separately with its own meta" do
      first = spawn_idle()
      second = spawn_idle()

      :ok = Watcher.watch(first, :first)
      :ok = Watcher.watch(second, :second)

      Process.exit(first, :kill)

      assert_receive {:process_down, ^first, :first, _reason}, 1_000
      refute_receive {:process_down, ^second, _meta, _reason}, 200

      assert find_watched(second), "killing one watch removed another"
    end
  end

  defp spawn_idle do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp wait_until_dead(pid, attempts \\ 100)

  defp wait_until_dead(pid, 0), do: flunk("#{inspect(pid)} never died")

  defp wait_until_dead(pid, attempts) do
    if Process.alive?(pid) do
      Process.sleep(10)
      wait_until_dead(pid, attempts - 1)
    end
  end

  defp find_watched(pid) do
    Enum.find(safe_watched(), fn {watched, _meta} -> watched == pid end)
  end

  defp safe_watched do
    Watcher.watched()
  rescue
    _error -> []
  end
end
