defmodule BeamSlackWeb.ChannelCase do
  @moduledoc """
  Test case for socket and channel tests.

  Channel tests run inside the SQL sandbox like any other test, but note that a
  channel is a *process*: anything it spawns or hands work to needs to be given
  access to the sandbox connection explicitly, or use a non-async test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint BeamSlackWeb.Endpoint

      import Phoenix.ChannelTest
      import BeamSlackWeb.ChannelCase
    end
  end

  setup tags do
    BeamSlack.DataCase.setup_sandbox(tags)
    :ok
  end
end
