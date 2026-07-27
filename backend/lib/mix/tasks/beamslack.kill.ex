defmodule Mix.Tasks.Beamslack.Kill do
  @shortdoc "Kills a named BeamSlack process and reports what came back"

  @moduledoc """
  Kills a named process in a running BeamSlack node, then reports whether
  something restarted in its place.

      mix beamslack.kill presence
      mix beamslack.kill repo --reason shutdown
      mix beamslack.kill --list

  This starts its own node and connects to the running server, because killing a
  process in a fresh `mix run` node would only kill a process in that node. Start
  the server with a name so it can be reached:

      # terminal 1
      bin/dev-node.sh a

      # terminal 2
      mix beamslack.kill presence

  Without a reachable node it falls back to a local start, which is useless for
  observing a browser tab but fine for seeing the mechanics.

  ## Options

    * `--list` — show the killable targets and whether each is alive
    * `--reason` — the exit reason, `kill` (untrappable, the default) or any other
      atom such as `shutdown`, which a process trapping exits can refuse
    * `--node` — the node to target, defaults to `beamslack_a@<hostname>`
    * `--cookie` — the distribution cookie, defaults to `beamslack`
  """

  use Mix.Task

  alias BeamSlack.Dev.Remote

  @impl Mix.Task
  def run(argv) do
    {opts, args, _invalid} =
      OptionParser.parse(argv,
        strict: [list: :boolean, reason: :string, node: :string, cookie: :string]
      )

    node = Remote.connect(opts)

    cond do
      opts[:list] ->
        list_targets(node)

      args == [] ->
        Mix.raise("usage: mix beamslack.kill TARGET [--reason shutdown]. Try --list.")

      true ->
        kill(node, hd(args), reason(opts))
    end
  end

  defp list_targets(node) do
    Mix.shell().info("Targets on #{node || "this node"}:\n")

    node
    |> Remote.call(BeamSlack.Dev.FaultInjection, :targets, [])
    |> Enum.each(fn target ->
      status = if target.pid, do: "alive   #{inspect(target.pid)}", else: "not running"
      Mix.shell().info("  #{String.pad_trailing(target.name, 20)} #{status}")
    end)
  end

  defp kill(node, target, reason) do
    Mix.shell().info("Killing #{target} with reason #{inspect(reason)} on #{node}...")

    case Remote.call(node, BeamSlack.Dev.FaultInjection, :kill, [target, reason]) do
      {:ok, %{pid: pid, tree_alive?: false}} ->
        Mix.shell().error("""
        #{target} was #{inspect(pid)}, and the entire application is now down.

        One killed process took the whole tree with it. The server log has the
        chain: find the first crash, then read every "failed to start" after it,
        then the "reached max_restarts" that ended it. Restart with bin/dev-node.sh.
        """)

      {:ok, %{pid: pid, restarted_as: nil}} ->
        Mix.shell().error("""
        #{target} was #{inspect(pid)} and is now gone, but the rest of the
        application is still up. Nothing restarted it.

        Either it is not supervised, or its supervisor gave up. Check the
        supervisor's :max_restarts and :max_seconds, and check the logs.
        """)

      {:ok, %{pid: pid, restarted_as: pid}} ->
        Mix.shell().info("""
        #{target} is still #{inspect(pid)}: the same process survived.

        It is trapping exits and declined a #{inspect(reason)}. Try --reason kill,
        which cannot be trapped.
        """)

      {:ok, %{pid: old, restarted_as: new}} ->
        Mix.shell().info("""
        #{target} was #{inspect(old)}, is now #{inspect(new)}.

        A supervisor restarted it. Note that this is a different process: any pid
        anyone was holding is now stale, and whatever state it had is gone. What
        did the browser do?
        """)

      {:error, :not_running} ->
        Mix.shell().error("#{target} is not running. Try --list.")

      {:error, :unknown_target} ->
        Mix.shell().error("Unknown target #{inspect(target)}. Try --list.")

      {:error, :disabled} ->
        Mix.shell().error("Fault injection is disabled outside dev and test.")
    end
  end

  defp reason(opts) do
    case opts[:reason] do
      nil -> :kill
      reason -> String.to_atom(reason)
    end
  end
end
