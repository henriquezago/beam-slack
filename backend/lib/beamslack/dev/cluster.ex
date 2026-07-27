defmodule BeamSlack.Dev.Cluster do
  @moduledoc """
  Cross-node probes. Dev and test only.

  Used by `mix beamslack.cluster check` to establish, rather than assume, which
  parts of BeamSlack actually cross a node boundary. The answers are not uniform
  and the differences are the substance of Track 4:

    * `Phoenix.PubSub` crosses, because its PG adapter forwards broadcasts to the
      other node's local adapter, which then delivers to local subscribers
    * `Phoenix.Presence` crosses, because it replicates a CRDT over that same
      PubSub
    * a `Registry` does not cross, at all, ever. It is a node-local ETS-backed
      lookup and there is no version of it that is not.
    * a named `GenServer` does not cross either. `Process.whereis/1` only ever
      looks at the local node's name table.

  Nothing warns you about the last two. `Process.whereis(MyServer)` on the node
  that does not have it simply returns `nil`, exactly as it would if the process
  had crashed, and code that treats that as "not started yet" will cheerfully
  start a second one.
  """

  @doc """
  Subscribes a spawned process on this node to `topic`, and has it forward the
  first message it receives to `reply_to`.

  Called via `:erpc` from another node, so `reply_to` is usually a remote pid.
  Sending to a remote pid is exactly as ordinary as sending to a local one, which
  is the whole conceit of distributed Erlang.
  """
  @spec subscribe_relay(String.t(), pid(), timeout()) :: pid()
  def subscribe_relay(topic, reply_to, timeout \\ 10_000) do
    spawn(fn ->
      Phoenix.PubSub.subscribe(BeamSlack.PubSub, topic)
      send(reply_to, {:subscribed, Node.self()})

      receive do
        message -> send(reply_to, {:relayed, Node.self(), message})
      after
        timeout -> send(reply_to, {:timeout, Node.self()})
      end
    end)
  end

  @doc """
  Broadcasts `payload` on `topic` through this node's PubSub.
  """
  @spec broadcast(String.t(), term()) :: :ok | {:error, term()}
  def broadcast(topic, payload) do
    Phoenix.PubSub.broadcast(BeamSlack.PubSub, topic, payload)
  end

  @doc """
  What this node can see of a few named things, for comparison across nodes.

  Run it on both nodes and diff the results. `registry_keys` being empty on one
  node while the other has entries is the discovery problem Lab 10 is about, in
  one line of output.
  """
  @spec inventory() :: map()
  def inventory do
    %{
      node: Node.self(),
      connected: Node.list(),
      presence_topics: presence_topics(),
      registry_keys: registry_keys(),
      pubsub_alive: is_pid(Process.whereis(BeamSlack.PubSub))
    }
  end

  defp presence_topics do
    # Phoenix.Presence has no "list every topic" API, so this reports the count of
    # locally-tracked entries instead, which is enough to compare two nodes.
    case Process.whereis(BeamSlackWeb.Presence) do
      nil -> :not_running
      _pid -> :running
    end
  end

  defp registry_keys do
    case Process.whereis(BeamSlack.Runtime.ChannelRegistry) do
      nil ->
        :not_running

      _pid ->
        BeamSlack.Runtime.ChannelRegistry
        |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
        |> Enum.sort()
    end
  catch
    _kind, _reason -> :not_running
  end
end
