import type { Notification } from '../api/types'

function kindLabel(kind: Notification['kind']): string {
  return kind === 'mention' ? 'mentioned you' : 'replied in a thread'
}

export function NotificationBell({
  notifications,
  unreadCount,
  open,
  onToggle,
  onMarkRead,
  onMarkAllRead,
  onOpenChannel,
}: {
  notifications: Notification[]
  unreadCount: number
  open: boolean
  onToggle: () => void
  onMarkRead: (id: string) => void
  onMarkAllRead: () => void
  onOpenChannel: (channelId: string) => void
}) {
  return (
    <div className="notification-bell">
      <button
        type="button"
        className="notification-bell__button"
        aria-label={unreadCount > 0 ? `${unreadCount} unread notifications` : 'Notifications'}
        onClick={onToggle}
      >
        Alerts
        {unreadCount > 0 && <span className="notification-bell__count">{unreadCount}</span>}
      </button>

      {open && (
        <div className="notification-panel" role="dialog" aria-label="Notifications">
          <header>
            <strong>Notifications</strong>
            {unreadCount > 0 && (
              <button type="button" onClick={() => void onMarkAllRead()}>
                Mark all read
              </button>
            )}
          </header>

          {notifications.length === 0 ? (
            <p className="muted pad">Nothing yet. Mentions and thread replies land here.</p>
          ) : (
            <ul>
              {notifications.map((notification) => (
                <li key={notification.id} className={notification.read_at ? '' : 'unread'}>
                  <button
                    type="button"
                    onClick={() => {
                      if (notification.read_at === null) void onMarkRead(notification.id)
                      onOpenChannel(notification.channel_id)
                    }}
                  >
                    <strong>{notification.message?.sender?.name ?? 'someone'}</strong>{' '}
                    {kindLabel(notification.kind)}
                    <span className="muted">{notification.message?.body}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  )
}
