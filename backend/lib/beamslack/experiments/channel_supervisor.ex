defmodule BeamSlack.Experiments.ChannelSupervisor do
  @moduledoc """
  Supervisor for the ChannelProcess.
  """

  alias BeamSlack.Experiments.ChannelProcess
  use Supervisor

  @doc "Start the supervisor for a channel."
  def start_link(channel_id) do
    Supervisor.start_link(__MODULE__, channel_id, name: __MODULE__)
  end

  @doc "Initialize the supervisor for a channel."
  def init(channel_id) do
    child = Supervisor.child_spec({ChannelProcess, channel_id}, restart: :transient)
    Supervisor.init([child], strategy: :one_for_one)
  end
end
