defmodule BeamSlack.Experiments.ChannelProcess do
  @moduledoc """
  Phase 2 experiment: a raw BEAM process holding ephemeral runtime state for one
  channel. Built only from `spawn/1`, `send/2`, and `receive`. Throwaway - Phase 3
  rebuilds it as a GenServer.

  State is carried as the argument to `loop/1`, never mutated. "Updating" the state
  means tail-calling `loop/1` with a new value.
  """

  # --- Client API (runs in the CALLER's process) ---

  @doc "Spawn the process for a channel and return its PID."
  def start(channel_id), do: spawn(fn -> loop(initial_state(channel_id)) end)

  @doc "Register a connected user (fire-and-forget message)."
  def join(pid, user) do
    send(pid, {:join, user})
    :ok
  end

  @doc "Remove a connected user (fire-and-forget message)."
  def leave(pid, user) do
    send(pid, {:leave, user})
    :ok
  end

  @doc """
  Request/reply: ask the process for its current state.

  Note the pattern: we include `self()` and a unique `ref` so the reply can be
  matched unambiguously. Your `loop/1` must satisfy this by replying with
  `{:state, ref, state}`.
  """
  def get_state(pid, timeout \\ 5000) do
    ref = make_ref()
    send(pid, {:get_state, self(), ref})

    receive do
      {:state, ^ref, state} -> state
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc "Kill the process (for the failure/ephemerality exercise)."
  def stop(pid), do: Process.exit(pid, :kill)

  # --- Server side (runs INSIDE the spawned process) ---

  defp initial_state(channel_id) do
    %{channel_id: channel_id, users: MapSet.new(), active_connections: 0}
  end

  @doc false
  defp loop(state) do
    receive do
      {:join, user} ->
        new_users = MapSet.put(state.users, user)
        new_active_connections = MapSet.size(new_users)
        loop(%{state | users: new_users, active_connections: new_active_connections})

      {:leave, user} ->
        new_users = MapSet.delete(state.users, user)
        new_active_connections = MapSet.size(new_users)
        loop(%{state | users: new_users, active_connections: new_active_connections})

      {:get_state, from, ref} ->
        send(from, {:state, ref, state})
        loop(state)
    end
  end
end
