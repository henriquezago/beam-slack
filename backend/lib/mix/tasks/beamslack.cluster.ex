defmodule Mix.Tasks.Beamslack.Cluster do
  @shortdoc "Inspects, connects, and partitions the BeamSlack cluster"

  @moduledoc """
  Looks at, joins, and breaks the connection between BeamSlack nodes.

      mix beamslack.cluster                    # who is up and who sees whom
      mix beamslack.cluster connect            # connect a and b
      mix beamslack.cluster check              # what actually crosses the boundary
      mix beamslack.cluster partition          # cut a from b, leaving both alive
      mix beamslack.cluster heal               # reconnect them

  Start the nodes first, in two terminals:

      bin/dev-node.sh a
      bin/dev-node.sh b

  ## Why "partition" is not "kill"

  Killing a node is easy and is not the interesting failure. In a partition both
  halves are perfectly healthy, both are serving users, and each believes the other
  is gone. There is no authority to appeal to and no way, from inside either half,
  to distinguish "the other node crashed" from "the network between us broke".
  That is not an implementation gap; it is a proof, and everything CAP has to say
  follows from it.

  `partition` is implemented with `Node.disconnect/1`, which is a clean break both
  sides notice immediately. A real partition is usually messier — packets stop
  arriving, and nobody notices until `:net_kernel`'s tick times out, which by
  default takes around 45 to 75 seconds. `--tick` reports that setting. The gap
  between "instant" and "a minute" is where most distributed bugs live.

  ## Options

    * `--nodes` — comma-separated snames, defaults to `beamslack_a,beamslack_b`
    * `--cookie` — defaults to `beamslack`
  """

  use Mix.Task

  alias BeamSlack.Dev.Remote

  @impl Mix.Task
  def run(argv) do
    {opts, args, _invalid} =
      OptionParser.parse(argv, strict: [nodes: :string, cookie: :string])

    nodes = nodes(opts)
    ensure_local_node(opts)

    case args do
      [] ->
        status(nodes)

      ["status"] ->
        status(nodes)

      ["connect"] ->
        connect(nodes)

      ["check"] ->
        check(nodes)

      ["partition"] ->
        partition(nodes)

      ["heal"] ->
        connect(nodes)

      [other] ->
        Mix.raise(
          "unknown command #{inspect(other)}. Try status, connect, check, partition, heal."
        )

      _many ->
        Mix.raise("one command at a time")
    end
  end

  defp status(nodes) do
    Mix.shell().info("")

    for node <- nodes do
      case reachable(node) do
        {:ok, seen} ->
          tick = call(node, :net_kernel, :get_net_ticktime, [])

          Mix.shell().info("""
          #{node}
            up, sees #{format_list(seen)}
            net_ticktime #{inspect(tick)}s -- a silent peer takes up to 4x this to be declared down
          """)

        :error ->
          Mix.shell().error(
            "#{node}\n  unreachable. Start it with bin/dev-node.sh #{suffix(node)}\n"
          )
      end
    end

    describe(nodes)
  end

  defp describe(nodes) do
    up = Enum.filter(nodes, &match?({:ok, _seen}, reachable(&1)))

    case up do
      [] ->
        Mix.shell().error("No nodes are up.")

      [_only] ->
        Mix.shell().info("Only one node is up. Start a second with bin/dev-node.sh b.")

      [first, second | _rest] ->
        {:ok, seen} = reachable(first)

        if second in seen do
          Mix.shell().info("The cluster is connected.")
        else
          Mix.shell().info("""
          The nodes are up but not connected. Each one believes it is alone, and
          each will happily serve users while replicating nothing.

              mix beamslack.cluster connect
          """)
        end
    end
  end

  defp connect([first | rest]) do
    for other <- rest do
      case call(first, Node, :connect, [other]) do
        true -> Mix.shell().info("#{first} <-> #{other} connected")
        result -> Mix.shell().error("#{first} -> #{other} failed: #{inspect(result)}")
      end
    end

    Process.sleep(500)
    status([first | rest])
  end

  defp check([first, second | _rest]) do
    topic = "cluster-check:#{System.unique_integer([:positive])}"

    Mix.shell().info("""

    Subscribing on #{second}, broadcasting from #{first}, on topic #{topic}.
    """)

    call(second, BeamSlack.Dev.Cluster, :subscribe_relay, [topic, self(), 5_000])

    receive do
      {:subscribed, node} -> Mix.shell().info("  subscribed on #{node}")
    after
      3_000 -> Mix.raise("the subscriber on #{second} never reported in")
    end

    call(first, BeamSlack.Dev.Cluster, :broadcast, [topic, {:hello, first}])

    receive do
      {:relayed, node, message} ->
        Mix.shell().info("""
          #{node} received #{inspect(message)}

        PubSub crossed the node boundary. It did that because its PG adapter
        forwarded the broadcast to the other node's adapter, which delivered it
        locally. Nothing you wrote arranged this.
        """)

      {:timeout, node} ->
        Mix.shell().error("""
          #{node} received nothing.

        Either the nodes are not connected, or they disagree about the PubSub
        server name. Run `mix beamslack.cluster` first.
        """)
    after
      6_000 -> Mix.shell().error("  no answer at all; is #{second} still up?")
    end

    inventories(first, second)
  end

  defp check(_nodes), do: Mix.raise("check needs two nodes. Start both with bin/dev-node.sh.")

  defp inventories(first, second) do
    Mix.shell().info("\nWhat each node can see locally:\n")

    for node <- [first, second] do
      Mix.shell().info(
        "  #{node}\n    #{inspect(call(node, BeamSlack.Dev.Cluster, :inventory, []))}\n"
      )
    end

    Mix.shell().info("""
    Compare `registry_keys`. Once Lab 01 is implemented and a channel runtime is
    started on one node, the other node's registry is still empty, and
    `ChannelRuntime.whereis/1` there returns nil. Two nodes will happily run two
    runtimes for the same channel. That is Lab 10.
    """)
  end

  defp partition([first | rest]) do
    Mix.shell().info("""

    Cutting #{first} off from #{format_list(rest)}.

    Both halves stay up. Before running this, predict: what does a browser on each
    node show? Does presence still list users from the other side? Do messages
    cross? How long until each side notices, and what notices?
    """)

    for other <- rest do
      call(first, Node, :disconnect, [other])
      Mix.shell().info("#{first} -x- #{other}")
    end

    Process.sleep(500)
    status([first | rest])

    Mix.shell().info("""
    Now watch both browsers for a minute before healing. Then:

        mix beamslack.cluster heal

    and watch what converges, how long it takes, and what never comes back.
    """)
  end

  defp reachable(node) do
    case call(node, Node, :list, []) do
      seen when is_list(seen) -> {:ok, Enum.reject(seen, &task_node?/1)}
      _other -> :error
    end
  end

  # This task's own throwaway node is connected to everything it inspects, which
  # is noise in every listing.
  defp task_node?(node) do
    node |> to_string() |> String.starts_with?("beamslack_task_")
  end

  defp call(node, module, function, args) do
    if Node.connect(node) == true do
      :erpc.call(node, module, function, args, 5_000)
    else
      :unreachable
    end
  catch
    _kind, _reason -> :unreachable
  end

  defp nodes(opts) do
    opts
    |> Keyword.get(:nodes, "beamslack_a,beamslack_b")
    |> String.split(",", trim: true)
    |> Enum.map(fn name ->
      if String.contains?(name, "@"), do: String.to_atom(name), else: :"#{name}@#{hostname()}"
    end)
  end

  defp ensure_local_node(opts) do
    # Reuses the same handshake the other tasks do; the target node it picks does
    # not matter here, only that this process is alive and has the cookie.
    Remote.connect(Keyword.put_new(opts, :node, "beamslack_a@#{hostname()}"))
  end

  defp suffix(node) do
    node |> to_string() |> String.split("@") |> hd() |> String.replace_prefix("beamslack_", "")
  end

  defp format_list([]), do: "nobody"
  defp format_list(nodes), do: Enum.map_join(nodes, ", ", &to_string/1)

  defp hostname do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end
end
