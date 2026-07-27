defmodule BeamSlackWeb.ReactionJSON do
  @moduledoc """
  Renders reaction summaries for the API and PubSub payloads.
  """

  def summary(%{reactions: reactions}), do: %{data: Enum.map(reactions, &summary_data/1)}

  def summary_data(summary) when is_map(summary) do
    %{
      emoji: summary.emoji || summary[:emoji],
      count: summary.count || summary[:count],
      user_ids: summary.user_ids || summary[:user_ids] || [],
      reacted: summary.reacted || summary[:reacted] || false
    }
  end
end
