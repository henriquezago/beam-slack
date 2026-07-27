defmodule BeamSlackWeb.ChangesetJSON do
  @moduledoc """
  Renders changeset validation errors for the JSON API.
  """

  @doc """
  Renders errors as `%{errors: %{field => ["message"]}}`.
  """
  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp translate_error({msg, opts}) do
    Regex.replace(~r/%{(\w+)}/, msg, fn _whole, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
