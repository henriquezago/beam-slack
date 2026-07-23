defmodule BeamSlack.Experiments.ChannelDynamicSupervisor do
  @moduledoc """
  Dynamic supervisor for the ChannelProcess.
  """
  alias BeamSlack.Experiments.ChannelProcess
  use DynamicSupervisor

  @doc "Start the dynamic supervisor for a channel."
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Initialize the dynamic supervisor for a channel."
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a channel process and return the PID."
  def start_channel(channel_id) do
    child_spec = Supervisor.child_spec({ChannelProcess, channel_id}, restart: :transient)
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc "Stop a channel process and return the result."
  def stop_channel(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
