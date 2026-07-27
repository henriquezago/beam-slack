defmodule BeamSlackWeb.DevController do
  @moduledoc """
  HTTP access to `BeamSlack.Dev.FaultInjection`, so faults can be triggered from a
  browser or curl while you watch the UI in another tab.

  Only routed in `:dev`. See the bottom of `BeamSlackWeb.Router`.
  """

  use BeamSlackWeb, :controller

  alias BeamSlack.Dev.FaultInjection
  alias BeamSlack.Dev.FloodTarget

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    json(conn, %{
      data: %{
        snapshot: normalize(FaultInjection.snapshot()),
        usage: %{
          "POST /dev/faults/kill/:target" => "kill a process, ?reason=shutdown to trap-test it",
          "POST /dev/faults/db" => "kill every Repo connection process",
          "POST /dev/faults/flood?count=10000" => "flood the slow target's mailbox",
          "GET /dev/faults/flood" => "observe the flood target without messaging it"
        }
      }
    })
  end

  @spec kill(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def kill(conn, %{"target" => target} = params) do
    reason = params |> Map.get("reason", "kill") |> String.to_atom()

    case FaultInjection.kill(target, reason) do
      {:ok, result} ->
        json(conn, %{
          data: %{
            target: target,
            reason: reason,
            was: inspect(result.pid),
            now: inspect(result.restarted_as),
            restarted: result.restarted_as not in [nil, result.pid]
          }
        })

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  @spec db(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def db(conn, _params) do
    case FaultInjection.drop_db_connections() do
      {:ok, result} -> json(conn, %{data: result})
      {:error, reason} -> conn |> put_status(422) |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  @spec flood(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def flood(conn, params) do
    count = params |> Map.get("count", "10000") |> String.to_integer()

    case FaultInjection.flood(count) do
      {:ok, result} -> json(conn, %{data: result})
      {:error, reason} -> conn |> put_status(422) |> json(%{errors: %{detail: inspect(reason)}})
    end
  end

  @spec observe(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def observe(conn, _params) do
    json(conn, %{data: normalize(FloodTarget.observe())})
  end

  # pids and atoms are not JSON, and inspecting them is more useful than dropping
  # them.
  defp normalize(term) when is_map(term) and not is_struct(term) do
    Map.new(term, fn {key, value} -> {key, normalize(value)} end)
  end

  defp normalize(term) when is_list(term), do: Enum.map(term, &normalize/1)
  defp normalize(term) when is_pid(term), do: inspect(term)
  defp normalize(term) when is_tuple(term), do: inspect(term)
  defp normalize(term), do: term
end
