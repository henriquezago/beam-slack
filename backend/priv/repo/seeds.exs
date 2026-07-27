# Populates the development database with a workspace you can actually log into.
#
#     mix run priv/repo/seeds.exs
#
# Safe to run more than once: every record is looked up before it is created.
#
# All of this is durable state. Nothing here is the runtime process state that
# the OTP labs deal with -- if you drop the database, this comes back by running
# the script again; if you kill a channel runtime, none of it is affected.

import Ecto.Query

alias BeamSlack.Accounts
alias BeamSlack.Channels
alias BeamSlack.Channels.Channel
alias BeamSlack.Messaging
alias BeamSlack.Messaging.Message
alias BeamSlack.Repo
alias BeamSlack.Workspaces
alias BeamSlack.Workspaces.Workspace

password = "password123"

people = [
  {"henrique", "henrique@example.com"},
  {"alice", "alice@example.com"},
  {"bob", "bob@example.com"},
  {"carol", "carol@example.com"}
]

users =
  Map.new(people, fn {name, email} ->
    user =
      case Accounts.get_user_by_email(email) do
        nil ->
          {:ok, user} =
            Accounts.register_user(%{name: name, email: email, password: password})

          user

        existing ->
          existing
      end

    {name, user}
  end)

owner = users["henrique"]

workspace =
  case Repo.one(from w in Workspace, where: w.name == "beam-crew" and w.owner_id == ^owner.id) do
    nil ->
      {:ok, workspace} = Workspaces.create_workspace(%{name: "beam-crew"}, owner.id)
      workspace

    existing ->
      existing
  end

for {name, user} <- users, name != "henrique" do
  unless Workspaces.member?(workspace.id, user.id) do
    {:ok, _member} = Workspaces.join_workspace(workspace.id, user.id)
  end
end

channel_specs = [
  {"general", "public", ["henrique", "alice", "bob", "carol"]},
  {"engineering", "public", ["henrique", "alice", "bob"]},
  {"random", "public", ["henrique", "carol"]},
  {"leadership", "private", ["henrique", "alice"]}
]

channels =
  Map.new(channel_specs, fn {name, type, member_names} ->
    channel =
      case Repo.one(from c in Channel, where: c.workspace_id == ^workspace.id and c.name == ^name) do
        nil ->
          {:ok, channel} =
            Channels.create_channel(%{workspace_id: workspace.id, name: name, type: type})

          channel

        existing ->
          existing
      end

    for member_name <- member_names do
      user = users[member_name]

      unless Channels.member?(channel.id, user.id) do
        {:ok, _member} = Channels.join_channel(channel.id, user.id)
      end
    end

    {name, channel}
  end)

history = [
  {"general", "henrique", "Welcome to BeamSlack. Everything you see here is durable state."},
  {"general", "alice", "Which means it survives a node restart, unlike presence."},
  {"general", "bob", "And unlike the typing indicator, which is deliberately disposable."},
  {"general", "carol", "So what exactly lives in the channel runtime process, then?"},
  {"general", "henrique", "Only what is meaningless after a crash. That is the whole rule."},
  {"engineering", "henrique", "Lab 01 is the Registry plus DynamicSupervisor lifecycle."},
  {"engineering", "alice", "The interesting part is that get_or_start is not atomic."},
  {"engineering", "bob", "Two joins for the same channel at the same instant. Who loses?"},
  {"random", "carol", "Does anyone actually enjoy writing recursive receive loops?"},
  {"random", "henrique", "Once. Then you appreciate why GenServer exists."},
  {"leadership", "henrique", "Private channel, so only its own members can read this."},
  {"leadership", "alice", "Good, that is the authorization rule we wanted to prove."}
]

for {channel_name, sender_name, body} <- history do
  channel = channels[channel_name]
  sender = users[sender_name]

  existing =
    Repo.one(
      from m in Message,
        where: m.channel_id == ^channel.id and m.sender_id == ^sender.id and m.body == ^body,
        limit: 1
    )

  unless existing do
    {:ok, _message} =
      Messaging.send_message(%{channel_id: channel.id, sender_id: sender.id, body: body})
  end
end

IO.puts("""

Seeded workspace "#{workspace.name}" with #{map_size(channels)} channels \
and #{map_size(users)} users.

Log in with any of these, password "#{password}":

#{Enum.map_join(people, "\n", fn {name, email} -> "  #{name} - #{email}" end)}
""")
