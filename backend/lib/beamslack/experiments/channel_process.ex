defmodule BeamSlack.Experiments.ChannelProcess do
  use GenServer

  @moduledoc """
  Phase 3 experiment: a GenServer holding ephemeral runtime state for one channel.
  """

  @doc "Spawn the process for a channel and return its PID."
  def start_link(channel_id), do: GenServer.start_link(__MODULE__, channel_id)

  def init(channel_id) do
    {:ok, initial_state(channel_id)}
  end

  def stop(pid), do: Process.exit(pid, :kill)

  def join(pid, user), do: GenServer.call(pid, {:join, user})
  def leave(pid, user), do: GenServer.call(pid, {:leave, user})
  def get_state(pid), do: GenServer.call(pid, :get_state)

  def handle_call({:join, user}, _from, state) do
    new_users = MapSet.put(state.users, user)
    new_active_connections = MapSet.size(new_users)
    {:reply, :ok, %{state | users: new_users, active_connections: new_active_connections}}
  end

  def handle_call({:leave, user}, _from, state) do
    new_users = MapSet.delete(state.users, user)
    new_active_connections = MapSet.size(new_users)
    {:reply, :ok, %{state | users: new_users, active_connections: new_active_connections}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp initial_state(channel_id) do
    %{channel_id: channel_id, users: MapSet.new(), active_connections: 0}
  end
end
