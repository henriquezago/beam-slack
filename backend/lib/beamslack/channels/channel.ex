defmodule BeamSlack.Channels.Channel do
  @moduledoc """
  Ecto schema for a channel. A channel belongs to a workspace and can be either
  public or private.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BeamSlack.Channels.ChannelMember
  alias BeamSlack.Workspaces.Workspace

  @types ~w(public private)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channels" do
    field :name, :string
    field :type, :string, default: "public"
    belongs_to :workspace, Workspace
    has_many :members, ChannelMember
    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid channel types.
  """
  def types, do: @types

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:workspace_id, :name, :type])
    |> validate_required([:workspace_id, :name, :type])
    |> validate_inclusion(:type, @types)
    |> assoc_constraint(:workspace)
    |> unique_constraint(:name, name: :channels_workspace_id_name_index)
  end
end
