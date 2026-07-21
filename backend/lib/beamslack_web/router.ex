defmodule BeamSlackWeb.Router do
  use BeamSlackWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", BeamSlackWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end
end
