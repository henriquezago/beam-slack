defmodule BeamSlackWeb.NotificationController do
  use BeamSlackWeb, :controller

  alias BeamSlack.Notifications

  action_fallback BeamSlackWeb.FallbackController

  def index(conn, _params) do
    user = conn.assigns.current_user
    notifications = Notifications.list_for_user(user.id)
    render(conn, :index, notifications: notifications)
  end

  def unread_count(conn, _params) do
    user = conn.assigns.current_user
    count = Notifications.unread_count(user.id)
    render(conn, :unread, count: count)
  end

  def mark_read(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, notification} <- Notifications.mark_read(id, user.id) do
      render(conn, :show, notification: BeamSlack.Repo.preload(notification, message: :sender))
    end
  end

  def mark_all_read(conn, _params) do
    user = conn.assigns.current_user
    {:ok, _count} = Notifications.mark_all_read(user.id)
    send_resp(conn, :no_content, "")
  end
end
