defmodule BeamSlack.Workspaces.Workspace do
  @moduledoc """
  Ecto schema for a workspace. A workspace is owned by a single user and
  groups together channels and members.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Workspaces.WorkspaceMember

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workspaces" do
    field :name, :string
    belongs_to :owner, User
    has_many :members, WorkspaceMember
    timestamps(type: :utc_datetime)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :owner_id])
    |> validate_required([:name, :owner_id])
    |> assoc_constraint(:owner)
    |> unique_constraint(:name, name: :workspaces_name_owner_id_index)
  end
end
