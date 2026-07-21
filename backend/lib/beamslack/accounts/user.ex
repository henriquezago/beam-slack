import Ecto.Changeset

defmodule BeamSlack.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    field :password_hash, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password_hash])
    |> validate_required([:name, :email, :password_hash])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password_hash, min: 8)
    |> put_password_hash()
    |> unique_constraint(:email)
    |> unique_constraint(:name)
  end

  defp put_password_hash(changeset) do
    if password = get_change(changeset, :password_hash) do
      put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    else
      changeset
    end
  end
end
