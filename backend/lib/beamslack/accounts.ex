defmodule BeamSlack.Accounts do
  @moduledoc """
  The Accounts module provides functions for managing user accounts in the BeamSlack application.
  It includes functionality for registering new users, retrieving user information, and updating user accounts.
  """

  import Ecto.Query
  alias BeamSlack.Accounts.User
  alias BeamSlack.Repo

  @doc """
  Registers a new user with the given attributes.

  Returns {:ok, %User{}} if the user is successfully registered, or {:error, %Ecto.Changeset{}} if the user is not registered.
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves a user by their ID.

  Returns %User{} if the user is found, or nil if the user is not found.
  """
  def get_user(id) do
    User
    |> where(id: ^id)
    |> Repo.one()
  end

  @doc """
  Retrieves a user by their email address.

  Returns %User{} if the user is found, or nil if the user is not found.
  """
  def get_user_by_email(email) do
    User
    |> where(email: ^email)
    |> Repo.one()
  end

  @doc """
  Authenticates a user by email and password.

  Returns {:ok, %User{}} on success, or {:error, :invalid_credentials} when the
  email is unknown or the password does not match. When the email is unknown we
  still run a dummy hash comparison so the response time does not reveal whether
  the account exists.
  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    case get_user_by_email(email) do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        if Bcrypt.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  def authenticate_user(_email, _password), do: {:error, :invalid_credentials}

  @doc """
  Retrieves all users.

  Returns a list of %User{} structs.
  """
  def list_users do
    User
    |> Repo.all()
  end

  @doc """
  Updates a user with the given attributes.

  Returns {:ok, %User{}} if the user is successfully updated, or {:error, %Ecto.Changeset{}} if the user is not updated.
  """
  def update_user(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  Returns {:ok, %User{}} if the user is successfully deleted, or {:error, %Ecto.Changeset{}} if the user is not deleted.
  """
  def delete_user(user) do
    Repo.delete(user)
  end
end
