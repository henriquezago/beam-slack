defmodule BeamSlackWeb.ChannelPresenceTest do
  @moduledoc """
  The specification for Lab 04. See `docs/labs/04-presence-architecture.md`.

  The wire protocol is fixed, because the React client is already written against
  `"presence_state"` and `"presence_diff"`. What is yours to decide is whether
  `Phoenix.Presence` is the source of truth or merely the transport, what metadata
  each connection carries, and how the channel process ends up tracking at all.

  Run with `mix test.labs`.
  """

  use BeamSlackWeb.ChannelCase, async: true

  @moduletag :lab

  import BeamSlack.Fixtures

  alias BeamSlackWeb.ChannelChannel
  alias BeamSlackWeb.Endpoint
  alias BeamSlackWeb.Presence
  alias BeamSlackWeb.UserSocket

  setup do
    user = user_fixture()
    {workspace, _owner} = workspace_fixture(user)
    channel = channel_fixture(workspace, %{name: "general"}, user.id)

    %{user: user, workspace: workspace, channel: channel, topic: "channel:#{channel.id}"}
  end

  defp join_as(user, topic) do
    user
    |> then(&socket(UserSocket, "user_socket:#{&1.id}", %{current_user: &1}))
    |> subscribe_and_join(ChannelChannel, topic)
  end

  describe "joining" do
    test "the joining connection is pushed the current presence state", %{
      user: user,
      topic: topic
    } do
      {:ok, _reply, _joined} = join_as(user, topic)

      assert_push "presence_state", _state, 1_000
    end

    test "the user is tracked under their own id", %{user: user, topic: topic} do
      {:ok, _reply, _joined} = join_as(user, topic)
      assert_push "presence_state", _state, 1_000

      assert Map.has_key?(Presence.list(topic), user.id),
             "presence is keyed by something other than the user id, so the client cannot match it to a user"
    end

    test "the metas carry the user's name", %{user: user, topic: topic} do
      {:ok, _reply, _joined} = join_as(user, topic)
      assert_push "presence_state", _state, 1_000

      assert %{metas: [meta | _rest]} = Presence.list(topic)[user.id]

      assert meta[:name] == user.name || meta["name"] == user.name,
             "the client renders presence by name, so a name must be in the metas: #{inspect(meta)}"
    end

    test "presence is per channel, not global", %{user: user, workspace: workspace, topic: topic} do
      other = channel_fixture(workspace, %{name: "random"})

      {:ok, _reply, _joined} = join_as(user, topic)
      assert_push "presence_state", _state, 1_000

      assert Presence.list("channel:#{other.id}") == %{}
    end
  end

  describe "several connections from one user" do
    test "count as one presence with two metas", %{user: user, topic: topic} do
      {:ok, _reply, _first} = join_as(user, topic)
      assert_push "presence_state", _state, 1_000

      Endpoint.subscribe(topic)
      {:ok, _reply, _second} = join_as(user, topic)

      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{joins: joins}},
                     1_000

      assert Map.has_key?(joins, user.id)

      presences = Presence.list(topic)

      assert map_size(presences) == 1, "two tabs became two users"
      assert length(presences[user.id].metas) == 2, "the second tab was not tracked separately"
    end

    test "closing one connection leaves the user present", %{user: user, topic: topic} do
      {:ok, _reply, _first} = join_as(user, topic)
      assert_push "presence_state", _state, 1_000
      {:ok, _reply, second} = join_as(user, topic)

      Endpoint.subscribe(topic)
      leave(second)

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "presence_diff",
                       payload: %{leaves: leaves}
                     },
                     1_000

      assert Map.has_key?(leaves, user.id)

      assert Map.has_key?(Presence.list(topic), user.id),
             "closing one of two tabs marked the user offline"
    end

    test "closing the last connection removes the user", %{user: user, topic: topic} do
      {:ok, _reply, only} = join_as(user, topic)
      assert_push "presence_state", _state, 1_000

      Endpoint.subscribe(topic)
      leave(only)

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "presence_diff",
                       payload: %{leaves: leaves}
                     },
                     1_000

      assert Map.has_key?(leaves, user.id)
      refute Map.has_key?(Presence.list(topic), user.id)
    end
  end

  describe "several users" do
    test "each is tracked separately", %{user: user, workspace: workspace, topic: topic} do
      other = user_fixture()
      {:ok, _member} = BeamSlack.Workspaces.join_workspace(workspace.id, other.id)

      {:ok, _reply, _first} = join_as(user, topic)
      assert_push "presence_state", _state, 1_000

      Endpoint.subscribe(topic)
      {:ok, _reply, _second} = join_as(other, topic)

      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 1_000

      presences = Presence.list(topic)

      assert map_size(presences) == 2
      assert Map.has_key?(presences, user.id)
      assert Map.has_key?(presences, other.id)
    end
  end
end
