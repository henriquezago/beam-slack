defmodule BeamSlack.Workspaces.WorkspaceMember do
  @moduledoc """
  Ecto schema for workspace membership. Associates a user with a workspace and
  the role they hold within it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Workspaces.Workspace

  @roles ~w(owner admin member)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workspace_members" do
    field :role, :string, default: "member"
    field :joined_at, :utc_datetime
    belongs_to :workspace, Workspace
    belongs_to :user, User
    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid roles.
  """
  def roles, do: @roles

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:workspace_id, :user_id, :role, :joined_at])
    |> validate_required([:workspace_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> put_joined_at()
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:user)
    |> unique_constraint([:workspace_id, :user_id],
      name: :workspace_members_workspace_id_user_id_index
    )
  end

  defp put_joined_at(changeset) do
    if get_field(changeset, :joined_at) do
      changeset
    else
      put_change(changeset, :joined_at, DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end
end
