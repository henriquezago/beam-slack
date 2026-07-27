defmodule BeamSlack.Runtime.RateLimiterTest do
  @moduledoc """
  The specification for Lab 07. See `docs/labs/07-ets-ownership.md`.

  The limit and window come from options so these tests do not have to wait a
  minute to see a window roll over. Your defaults should come from
  `Application.get_env(:beamslack, :rate_limit)`.

  The survival test is the one that matters. Everything else is arithmetic.

  `async: false`, because the table is global and one test kills its owner.

  Run with `mix test.labs`.
  """

  use ExUnit.Case, async: false

  @moduletag :lab

  alias BeamSlack.Runtime.RateLimiter

  @opts [limit: 3, window_ms: 200]

  setup do
    safe_reset_all()
    %{key: "user-#{System.unique_integer([:positive])}"}
  end

  describe "the limit" do
    test "allows actions up to the limit", %{key: key} do
      assert {:ok, 2} = RateLimiter.hit(key, @opts)
      assert {:ok, 1} = RateLimiter.hit(key, @opts)
      assert {:ok, 0} = RateLimiter.hit(key, @opts)
    end

    test "refuses the one after that, with a retry hint", %{key: key} do
      for _each <- 1..3, do: RateLimiter.hit(key, @opts)

      assert {:error, :rate_limited, retry_after} = RateLimiter.hit(key, @opts)
      assert retry_after > 0
      assert retry_after <= 200
    end

    test "keys are independent", %{key: key} do
      other = "#{key}-other"

      for _each <- 1..3, do: RateLimiter.hit(key, @opts)

      assert {:error, :rate_limited, _retry} = RateLimiter.hit(key, @opts)
      assert {:ok, 2} = RateLimiter.hit(other, @opts)
    end

    test "the window rolls over", %{key: key} do
      for _each <- 1..3, do: RateLimiter.hit(key, @opts)
      assert {:error, :rate_limited, _retry} = RateLimiter.hit(key, @opts)

      Process.sleep(250)

      assert {:ok, _remaining} = RateLimiter.hit(key, @opts)
    end
  end

  describe "remaining/2" do
    test "reports without consuming", %{key: key} do
      assert RateLimiter.remaining(key, @opts) == 3
      assert RateLimiter.remaining(key, @opts) == 3

      {:ok, _remaining} = RateLimiter.hit(key, @opts)

      assert RateLimiter.remaining(key, @opts) == 2
    end

    test "reads do not go through a process" do
      # If the limiter's reads are GenServer calls, killing the owner mid-read
      # would matter and this would be a very different test. Instead: a read from
      # a process that has never spoken to the limiter must work, and must work
      # while the owning process is busy.
      key = "concurrent-read"
      {:ok, _remaining} = RateLimiter.hit(key, @opts)

      task = Task.async(fn -> RateLimiter.remaining(key, @opts) end)

      assert Task.await(task, 500) == 2
    end
  end

  describe "concurrency" do
    test "a hundred simultaneous hits count exactly a hundred times" do
      key = "stampede"
      opts = [limit: 1_000, window_ms: 5_000]

      1..100
      |> Task.async_stream(fn _each -> RateLimiter.hit(key, opts) end,
        max_concurrency: 50,
        ordered: false
      )
      |> Stream.run()

      assert RateLimiter.remaining(key, opts) == 900,
             "the counter lost updates, so the increment is not atomic"
    end

    test "exactly the limit is granted when everyone arrives at once" do
      key = "thundering-herd"
      opts = [limit: 10, window_ms: 5_000]

      results =
        1..50
        |> Task.async_stream(fn _each -> RateLimiter.hit(key, opts) end,
          max_concurrency: 50,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      granted = Enum.count(results, &match?({:ok, _remaining}, &1))

      assert granted == 10,
             "#{granted} callers were allowed through a limit of 10; check-then-write is not atomic"
    end
  end

  describe "reset" do
    test "reset/1 clears one key", %{key: key} do
      for _each <- 1..3, do: RateLimiter.hit(key, @opts)
      assert :ok = RateLimiter.reset(key)

      assert RateLimiter.remaining(key, @opts) == 3
    end

    test "reset_all/0 clears everything", %{key: key} do
      RateLimiter.hit(key, @opts)
      RateLimiter.hit("#{key}-other", @opts)

      assert :ok = RateLimiter.reset_all()

      assert RateLimiter.remaining(key, @opts) == 3
      assert RateLimiter.remaining("#{key}-other", @opts) == 3
    end
  end

  describe "surviving the owner" do
    test "the table outlives its owning process", %{key: key} do
      {:ok, 2} = RateLimiter.hit(key, @opts)

      owner = table_owner()
      assert is_pid(owner), "the table has no owner, which should be impossible"

      Process.exit(owner, :kill)
      wait_for_new_owner(owner)

      # An ETS table dies with its owner unless somebody inherits it. Whether the
      # *counts* survive is your call -- a rate limiter that forgets on restart is
      # defensible. What is not defensible is the next call crashing because the
      # table is gone.
      assert is_integer(RateLimiter.remaining(key, @opts)),
             "the table went with its owner and the limiter is now broken"

      assert {:ok, _remaining} = RateLimiter.hit(key, @opts)
    end

    test "the limiter still limits after its owner is replaced" do
      key = "post-crash"
      for _each <- 1..3, do: RateLimiter.hit(key, @opts)

      owner = table_owner()
      Process.exit(owner, :kill)
      wait_for_new_owner(owner)

      for _each <- 1..3, do: RateLimiter.hit(key, @opts)

      assert {:error, :rate_limited, _retry} = RateLimiter.hit(key, @opts),
             "the limit is not enforced after a restart, so a crash is a way around it"
    end
  end

  defp table_owner do
    :ets.info(RateLimiter.table(), :owner)
  rescue
    _error -> nil
  end

  defp wait_for_new_owner(old_owner, attempts \\ 100)

  defp wait_for_new_owner(_old_owner, 0), do: flunk("the table never got a new owner")

  defp wait_for_new_owner(old_owner, attempts) do
    case table_owner() do
      ^old_owner ->
        Process.sleep(20)
        wait_for_new_owner(old_owner, attempts - 1)

      nil ->
        Process.sleep(20)
        wait_for_new_owner(old_owner, attempts - 1)

      _new_owner ->
        :ok
    end
  end

  defp safe_reset_all do
    RateLimiter.reset_all()
  rescue
    _error -> :ok
  end
end
