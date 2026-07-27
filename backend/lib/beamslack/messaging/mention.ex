defmodule BeamSlack.Messaging.Mention do
  @moduledoc """
  Ecto schema for "this message mentions this user".

  Derived from the message body at write time rather than parsed on read. That is
  a deliberate trade: renaming a user leaves old mentions pointing at the right
  person by id while the rendered text says the old name, which is the behavior
  most chat products settle on.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Messaging.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "mentions" do
    belongs_to :message, Message
    belongs_to :user, User
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:message_id, :user_id])
    |> validate_required([:message_id, :user_id])
    |> assoc_constraint(:message)
    |> assoc_constraint(:user)
    |> unique_constraint([:message_id, :user_id],
      name: :mentions_message_id_user_id_index
    )
  end
end
