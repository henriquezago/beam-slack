defmodule BeamSlackWeb.ChannelTypingTest do
  @moduledoc """
  The specification for Lab 05. See `docs/labs/05-typing-indicators.md`.

  The expiry window comes from `Application.get_env(:beamslack, :typing_timeout)`,
  which `config/test.exs` sets to 100ms so these tests do not have to sleep
  through three seconds. Read it in your implementation rather than hardcoding a
  number.

  The test that matters most is "a second keystroke replaces the first timer".
  Forgetting to cancel is the classic bug, and it shows up as two
  `"typing_stopped"` broadcasts instead of one.

  Run with `mix test.labs`.
  """

  use BeamSlackWeb.ChannelCase, async: true

  @moduletag :lab

  import BeamSlack.Fixtures

  alias BeamSlack.Messaging
  alias BeamSlackWeb.ChannelChannel
  alias BeamSlackWeb.UserSocket

  @timeout Application.compile_env(:beamslack, :typing_timeout, 3_000)

  setup do
    user = user_fixture()
    {workspace, _owner} = workspace_fixture(user)
    channel = channel_fixture(workspace, %{name: "general"}, user.id)

    socket = socket(UserSocket, "user_socket:#{user.id}", %{current_user: user})
    {:ok, _reply, joined} = subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")

    %{user: user, channel: channel, joined: joined}
  end

  describe "typing" do
    test "a keystroke broadcasts that the user started typing", %{joined: joined, user: user} do
      push(joined, "typing", %{})

      assert_broadcast "typing_started", payload, 1_000
      assert payload.user_id == user.id
      assert payload.name == user.name
    end

    test "the typing state expires on its own", %{joined: joined, user: user} do
      push(joined, "typing", %{})
      assert_broadcast "typing_started", _payload, 1_000

      assert_broadcast "typing_stopped", %{user_id: user_id}, @timeout * 10
      assert user_id == user.id
    end

    test "a second keystroke replaces the first timer", %{joined: joined} do
      push(joined, "typing", %{})
      push(joined, "typing", %{})

      assert_broadcast "typing_stopped", _payload, @timeout * 10

      refute_broadcast "typing_stopped", _payload, @timeout * 3
    end

    test "several keystrokes still expire exactly once", %{joined: joined} do
      for _keystroke <- 1..5, do: push(joined, "typing", %{})

      assert_broadcast "typing_stopped", _payload, @timeout * 10
      refute_broadcast "typing_stopped", _payload, @timeout * 3
    end

    test "typing never persists anything", %{joined: joined, channel: channel} do
      push(joined, "typing", %{})
      assert_broadcast "typing_started", _payload, 1_000
      assert_broadcast "typing_stopped", _payload, @timeout * 10

      assert Messaging.list_messages(channel.id) == [],
             "a typing indicator wrote to the database"
    end

    test "the channel process stays alive across the whole cycle", %{joined: joined} do
      push(joined, "typing", %{})
      assert_broadcast "typing_started", _payload, 1_000
      assert_broadcast "typing_stopped", _payload, @timeout * 10

      assert Process.alive?(joined.channel_pid),
             "the expiry message was not handled, so the channel crashed on an unexpected info"
    end
  end

  describe "several users typing" do
    setup %{channel: channel} do
      other = user_fixture()
      {:ok, _member} = BeamSlack.Channels.join_channel(channel.id, other.id)
      {:ok, _member} = BeamSlack.Workspaces.join_workspace(channel.workspace_id, other.id)

      socket = socket(UserSocket, "user_socket:#{other.id}", %{current_user: other})
      {:ok, _reply, joined} = subscribe_and_join(socket, ChannelChannel, "channel:#{channel.id}")

      %{other: other, other_socket: joined}
    end

    test "each user's timer is tracked separately", %{
      joined: joined,
      other_socket: other_socket,
      user: user,
      other: other
    } do
      push(joined, "typing", %{})
      push(other_socket, "typing", %{})

      started =
        for _each <- 1..2 do
          assert_broadcast "typing_started", payload, 1_000
          payload.user_id
        end

      assert Enum.sort(started) == Enum.sort([user.id, other.id])

      stopped =
        for _each <- 1..2 do
          assert_broadcast "typing_stopped", payload, @timeout * 10
          payload.user_id
        end

      assert Enum.sort(stopped) == Enum.sort([user.id, other.id]),
             "one user's expiry cancelled another user's timer"
    end
  end
end
