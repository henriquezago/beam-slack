defmodule BeamSlackWeb.Router do
  use BeamSlackWeb, :router

  import BeamSlackWeb.Auth, only: [fetch_current_user: 2, require_authenticated_user: 2]

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_current_user
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  scope "/api", BeamSlackWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/users", UserController, :create
    post "/session", SessionController, :create
  end

  scope "/api", BeamSlackWeb do
    pipe_through [:api, :authenticated]

    get "/me", UserController, :me
    get "/users", UserController, :index

    get "/workspaces", WorkspaceController, :index
    post "/workspaces", WorkspaceController, :create
    get "/workspaces/:id", WorkspaceController, :show
    get "/workspaces/:id/members", WorkspaceController, :members
    post "/workspaces/:id/join", WorkspaceController, :join

    get "/workspaces/:workspace_id/channels", ChannelController, :index
    post "/workspaces/:workspace_id/channels", ChannelController, :create

    get "/channels/:id", ChannelController, :show
    get "/channels/:id/members", ChannelController, :members
    post "/channels/:id/join", ChannelController, :join

    get "/channels/:channel_id/messages", MessageController, :index
    post "/channels/:channel_id/messages", MessageController, :create

    get "/messages/:id/thread", MessageController, :thread
    post "/messages/:id/reactions", MessageController, :add_reaction
    delete "/messages/:id/reactions", MessageController, :remove_reaction

    get "/notifications", NotificationController, :index
    get "/notifications/unread_count", NotificationController, :unread_count
    post "/notifications/read_all", NotificationController, :mark_all_read
    post "/notifications/:id/read", NotificationController, :mark_read
  end

  # Everything below is dev-only and deliberately dangerous. It is compiled out of
  # every other environment rather than guarded at runtime.
  if Application.compile_env(:beamslack, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard",
        metrics: BeamSlackWeb.Telemetry,
        ecto_repos: [BeamSlack.Repo]
    end

    scope "/dev/faults", BeamSlackWeb do
      pipe_through :api

      get "/", DevController, :index
      get "/flood", DevController, :observe
      post "/kill/:target", DevController, :kill
      post "/db", DevController, :db
      post "/flood", DevController, :flood
    end
  end
end
