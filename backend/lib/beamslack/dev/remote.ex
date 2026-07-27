defmodule BeamSlack.Dev.Remote do
  @moduledoc """
  Connects a mix task to a running BeamSlack node, so that a fault is injected
  where the browser is connected rather than in a throwaway node.

  This is the smallest useful piece of distributed Erlang: name the local node,
  agree on a cookie, `Node.connect/1`, then `:erpc.call/4`. There is no broker, no
  service discovery, and no protocol to define — a remote call is a function call
  with a node name in front of it. That transparency is the point of distributed
  Erlang and also its trap, since a call across a partitioned network looks
  exactly like a slow function until it times out.

  Track 4 goes further with this. Here it is only plumbing.
  """

  @default_cookie :beamslack
  # Matches `bin/dev-node.sh a`, which is the node the frontend proxies to.
  @default_sname "beamslack_a"

  @doc """
  Ensures this node is alive and connected to the target, returning the target's
  node name, or nil when the target is unreachable and work should happen locally.
  """
  @spec connect(keyword()) :: node() | nil
  def connect(opts \\ []) do
    cookie = opts |> Keyword.get(:cookie, to_string(@default_cookie)) |> String.to_atom()
    target = target_node(opts)

    ensure_distribution(cookie)

    if Node.connect(target) == true do
      target
    else
      Mix.shell().error("""
      Could not reach #{target}. Running against this node instead, which means
      nothing you break here is what your browser is talking to.

      Start the server with a name so it can be reached:

          bin/dev-node.sh a

      or target a different node with --node beamslack_b@#{hostname()}.
      """)

      Application.ensure_all_started(:beamslack)
      nil
    end
  end

  @doc """
  Calls `module.function(args)` on `node`, or locally when `node` is nil.
  """
  @spec call(node() | nil, module(), atom(), [term()]) :: term()
  def call(nil, module, function, args), do: apply(module, function, args)

  def call(node, module, function, args) do
    :erpc.call(node, module, function, args, 15_000)
  catch
    :error, {:erpc, :timeout} ->
      {:error, :timeout}

    :error, {:exception, exception, _stack} ->
      {:error, exception}
  end

  @doc """
  The node name a task targets, from `--node`, then `BEAMSLACK_NODE`, then the
  default sname on this host.
  """
  @spec target_node(keyword()) :: node()
  def target_node(opts \\ []) do
    name =
      opts[:node] || System.get_env("BEAMSLACK_NODE") ||
        "#{@default_sname}@#{hostname()}"

    String.to_atom(name)
  end

  defp ensure_distribution(cookie) do
    unless Node.alive?() do
      name = :"beamslack_task_#{System.unique_integer([:positive])}@#{hostname()}"
      {:ok, _pid} = Node.start(name, :shortnames)
    end

    Node.set_cookie(Node.self(), cookie)
  end

  defp hostname do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end
end
