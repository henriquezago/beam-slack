defmodule BeamSlack.Runtime.IngestTest do
  @moduledoc """
  The specification for Lab 08. See `docs/labs/08-backpressure.md`.

  The central assertion is bookkeeping, not throughput: everything accepted must
  eventually be completed, and the queue must never exceed the bound. A design
  that achieves those two by rejecting almost everything passes, and that is fine —
  rejecting is a legitimate answer. Silently dropping accepted work is not.

  `async: false`, and slow on purpose: several tests wait for a deliberately slow
  consumer to catch up.

  Run with `mix test.labs`.
  """

  use ExUnit.Case, async: false

  @moduletag :lab

  alias BeamSlack.Runtime.Ingest

  # Small enough to fill quickly, slow enough that filling it is possible.
  @opts [max_queue: 20, cost_ms: 2]

  setup do
    assert is_pid(Process.whereis(Ingest)),
           "BeamSlack.Runtime.Ingest is not running. Add it to the supervision tree."

    Ingest.reset()
    on_exit(fn -> safe_reset() end)
    :ok
  end

  describe "the happy path" do
    test "work submitted slowly is always accepted" do
      for n <- 1..10 do
        assert Ingest.submit({:work, n}, @opts) == :ok
        Process.sleep(5)
      end

      wait_until_drained()

      assert %{accepted: 10, rejected: 0, completed: 10} = Ingest.stats()
    end

    test "queue_len/0 answers while work is queued" do
      for n <- 1..15, do: Ingest.submit({:work, n}, @opts)

      assert is_integer(Ingest.queue_len())

      wait_until_drained()
    end
  end

  describe "under flood" do
    test "the queue never exceeds max_queue" do
      task =
        Task.async(fn ->
          Enum.map(1..2_000, fn n -> Ingest.submit({:work, n}, @opts) end)
        end)

      peak =
        Enum.reduce(1..40, 0, fn _sample, peak ->
          Process.sleep(10)
          max(peak, Ingest.queue_len())
        end)

      Task.await(task, 30_000)

      assert peak <= 20,
             "the queue reached #{peak} against a bound of 20, so the bound is not enforced"
    end

    test "excess work is refused rather than accepted and dropped" do
      results = Enum.map(1..2_000, fn n -> Ingest.submit({:work, n}, @opts) end)

      rejected = Enum.count(results, &match?({:error, :overloaded, _len}, &1))

      assert rejected > 0,
             "2000 units were all accepted by a queue bounded at 20; nothing is being refused"
    end

    test "a rejection reports the queue length so a caller can back off" do
      Enum.each(1..2_000, fn n -> Ingest.submit({:work, n}, @opts) end)

      case Ingest.submit(:one_more, @opts) do
        {:error, :overloaded, len} -> assert is_integer(len) and len >= 0
        :ok -> :ok
      end

      wait_until_drained()
    end

    test "everything accepted is eventually completed" do
      results = Enum.map(1..1_000, fn n -> Ingest.submit({:work, n}, @opts) end)
      accepted = Enum.count(results, &(&1 == :ok))

      wait_until_drained()

      stats = Ingest.stats()

      assert stats.accepted == accepted

      assert stats.completed == accepted,
             "#{accepted - stats.completed} accepted units were never completed, which means they were dropped after being acknowledged"
    end

    test "the submitting process is never blocked for long" do
      # Whatever mechanism you chose, a submit must return promptly. A call to a
      # process that is 2000 units behind will not, which is the trap.
      Enum.each(1..500, fn n -> Ingest.submit({:work, n}, @opts) end)

      {micros, _result} = :timer.tc(fn -> Ingest.submit(:timed, @opts) end)

      assert micros < 500_000,
             "a single submit took #{div(micros, 1000)}ms; the caller is absorbing the backlog"

      wait_until_drained()
    end
  end

  describe "recovery" do
    test "the intake accepts again once it has caught up" do
      Enum.each(1..2_000, fn n -> Ingest.submit({:work, n}, @opts) end)

      wait_until_drained()

      assert Ingest.submit(:after_the_storm, @opts) == :ok
    end

    test "the intake survives the flood" do
      pid = Process.whereis(Ingest)

      Enum.each(1..2_000, fn n -> Ingest.submit({:work, n}, @opts) end)
      wait_until_drained()

      assert Process.whereis(Ingest) == pid,
             "the intake crashed and was restarted, which is not the same as handling overload"
    end

    test "the mailbox is not where the backlog lives" do
      Enum.each(1..2_000, fn n -> Ingest.submit({:work, n}, @opts) end)

      pid = Process.whereis(Ingest)
      {:message_queue_len, mailbox} = Process.info(pid, :message_queue_len)

      assert mailbox <= 100,
             "#{mailbox} messages are sitting in the mailbox; the bound is being tracked but not enforced, and the unbounded thing is still unbounded"

      wait_until_drained()
    end
  end

  defp wait_until_drained(attempts \\ 600)

  defp wait_until_drained(0), do: flunk("the intake never drained")

  defp wait_until_drained(attempts) do
    if Ingest.queue_len() > 0 do
      Process.sleep(50)
      wait_until_drained(attempts - 1)
    end
  end

  defp safe_reset do
    Ingest.reset()
  rescue
    _error -> :ok
  end
end
