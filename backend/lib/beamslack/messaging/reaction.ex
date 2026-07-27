defmodule BeamSlack.Messaging.Reaction do
  @moduledoc """
  Ecto schema for one user's emoji reaction to one message.

  The unique index on `{message_id, user_id, emoji}` is the real constraint;
  `unique_constraint/3` here only turns the database's rejection into a changeset
  error. Two simultaneous requests both pass every validation, and only the
  database sees both.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BeamSlack.Accounts.User
  alias BeamSlack.Messaging.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  # Anything outside this list is rejected. A free-text emoji column invites
  # arbitrary strings into a field the UI renders directly.
  @emojis ~w(👍 👎 ❤️ 🎉 😄 😕 🚀 👀 🔥 ✅)

  schema "reactions" do
    field :emoji, :string
    belongs_to :message, Message
    belongs_to :user, User
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The emoji a reaction is allowed to be."
  @spec emojis() :: [String.t()]
  def emojis, do: @emojis

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:message_id, :user_id, :emoji])
    |> validate_required([:message_id, :user_id, :emoji])
    |> validate_inclusion(:emoji, @emojis)
    |> assoc_constraint(:message)
    |> assoc_constraint(:user)
    |> unique_constraint([:message_id, :user_id, :emoji],
      name: :reactions_message_id_user_id_emoji_index,
      message: "has already been added"
    )
  end
end
