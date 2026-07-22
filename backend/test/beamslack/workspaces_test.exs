defmodule BeamSlack.WorkspacesTest do
  @moduledoc """
  Tests for the Workspaces context.
  """

  use BeamSlack.DataCase, async: true

  import BeamSlack.Fixtures

  alias BeamSlack.Workspaces
  alias BeamSlack.Workspaces.Workspace

  describe "create_workspace/2" do
    test "creates a workspace and adds the owner as an owner member" do
      owner = user_fixture()

      assert {:ok, %Workspace{} = workspace} =
               Workspaces.create_workspace(%{name: "Acme"}, owner.id)

      assert workspace.name == "Acme"
      assert workspace.owner_id == owner.id

      assert [member] = Workspaces.list_members(workspace.id)
      assert member.user_id == owner.id
      assert member.role == "owner"
      assert member.user.id == owner.id
    end

    test "returns an error when name is missing" do
      owner = user_fixture()
      assert {:error, changeset} = Workspaces.create_workspace(%{}, owner.id)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "enforces unique workspace name per owner" do
      owner = user_fixture()
      assert {:ok, _} = Workspaces.create_workspace(%{name: "Dup"}, owner.id)
      assert {:error, changeset} = Workspaces.create_workspace(%{name: "Dup"}, owner.id)
      assert "has already been taken" in errors_on(changeset).name
    end

    test "different owners can reuse the same name" do
      {_workspace, _owner} = workspace_fixture(nil, %{name: "Shared"})
      other_owner = user_fixture()
      assert {:ok, _} = Workspaces.create_workspace(%{name: "Shared"}, other_owner.id)
    end
  end

  describe "join_workspace/3" do
    test "adds a member with the default role" do
      {workspace, _owner} = workspace_fixture()
      user = user_fixture()

      assert {:ok, member} = Workspaces.join_workspace(workspace.id, user.id)
      assert member.role == "member"
    end

    test "prevents a user from joining the same workspace twice" do
      {workspace, _owner} = workspace_fixture()
      user = user_fixture()

      assert {:ok, _} = Workspaces.join_workspace(workspace.id, user.id)
      assert {:error, changeset} = Workspaces.join_workspace(workspace.id, user.id)
      assert Keyword.has_key?(changeset.errors, :workspace_id)
    end

    test "rejects invalid roles" do
      {workspace, _owner} = workspace_fixture()
      user = user_fixture()

      assert {:error, changeset} = Workspaces.join_workspace(workspace.id, user.id, "superuser")
      assert "is invalid" in errors_on(changeset).role
    end
  end

  describe "get_workspace/1" do
    test "returns the workspace" do
      {workspace, _owner} = workspace_fixture()
      assert Workspaces.get_workspace(workspace.id).id == workspace.id
    end

    test "returns nil for a missing workspace" do
      assert Workspaces.get_workspace(Ecto.UUID.generate()) == nil
    end
  end
end
