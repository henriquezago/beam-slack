defmodule Mix.Tasks.Beamslack.Flood do
  @shortdoc "Floods a process faster than it can drain, and watches the mailbox grow"

  @moduledoc """
  Sends N messages to `BeamSlack.Dev.FloodTarget`, which handles each one slowly on
  purpose, and prints the mailbox length until it drains.

      mix beamslack.flood
      mix beamslack.flood --count 50000 --watch
      mix beamslack.flood --target repo --count 1000

  What to look for:

    * the mailbox length climbing far past anything you would consider reasonable,
      with no error anywhere, because `send/2` cannot fail
    * `memory_kb` growing in step with it, since the mailbox is on the process heap
    * the drain rate being constant and completely independent of the arrival rate
    * `BeamSlack.Dev.FloodTarget.stats/0` timing out while `observe/0` still
      answers instantly. Those two calls differ only in whether they require the
      target process to do anything.

  Then the questions Lab 08 asks: at what queue length is this process's output
  useless even though it is still working? What should have happened instead, and
  who was supposed to notice — the sender, the receiver, or something between
  them?

  ## Options

    * `--count` — how many messages to send, default 10000
    * `--target` — a name from `mix beamslack.kill --list`, default the flood target
    * `--watch` — poll and print until the mailbox is empty
    * `--node`, `--cookie` — as in `mix beamslack.kill`
  """

  use Mix.Task

  alias BeamSlack.Dev.FaultInjection
  alias BeamSlack.Dev.FloodTarget
  alias BeamSlack.Dev.Remote

  @impl Mix.Task
  def run(argv) do
    {opts, _args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          count: :integer,
          target: :string,
          watch: :boolean,
          node: :string,
          cookie: :string
        ]
      )

    node = Remote.connect(opts)
    count = Keyword.get(opts, :count, 10_000)

    before = Remote.call(node, FloodTarget, :observe, [])
    Mix.shell().info("before:  #{format(before)}")

    case Remote.call(node, FaultInjection, :flood, [count, flood_opts(opts)]) do
      {:ok, %{sent: sent}} ->
        Mix.shell().info("sent:    #{sent} messages\n")
        if opts[:watch], do: watch(node), else: sample(node)

      {:error, :not_running} ->
        Mix.shell().error("""
        The flood target is not running. It only starts in dev and test; make sure
        the server you are pointing at was started with MIX_ENV=dev.
        """)

      {:error, reason} ->
        Mix.shell().error("flood failed: #{inspect(reason)}")
    end
  end

  defp flood_opts(opts) do
    case opts[:target] do
      nil -> []
      "flood_target" -> []
      "repo" -> [target: BeamSlack.Repo]
      "presence" -> [target: BeamSlackWeb.Presence]
      other -> Mix.raise("unsupported flood target #{inspect(other)}")
    end
  end

  defp sample(node) do
    Process.sleep(200)
    Mix.shell().info("after:   #{format(Remote.call(node, FloodTarget, :observe, []))}")

    Mix.shell().info("""

    Run again with --watch to see it drain. While it is draining, try:

        mix beamslack.kill flood_target

    and note what happens to the queued work.
    """)
  end

  defp watch(node, previous \\ nil, stable \\ 0) do
    Process.sleep(500)
    info = Remote.call(node, FloodTarget, :observe, [])

    Mix.shell().info("watch:   #{format(info)}#{rate(info, previous)}")

    cond do
      match?(%{mailbox_len: 0}, info) and stable > 1 ->
        Mix.shell().info("\ndrained.")

      match?(%{mailbox_len: 0}, info) ->
        watch(node, info, stable + 1)

      true ->
        watch(node, info, 0)
    end
  end

  defp rate(%{mailbox_len: current}, %{mailbox_len: previous}) do
    "  (#{round((previous - current) / 0.5)}/s draining)"
  end

  defp rate(_info, _previous), do: ""

  defp format(%{mailbox_len: len, memory_kb: memory, status: status}) do
    "mailbox #{String.pad_leading(to_string(len), 8)}   #{String.pad_leading(to_string(memory), 6)} KB   #{status}"
  end

  defp format(other), do: inspect(other)
end
