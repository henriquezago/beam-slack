import { useState, type FormEvent } from 'react'
import { NavLink, useNavigate } from 'react-router-dom'
import { api } from '../api/client'
import type { Channel, ChannelType, Workspace } from '../api/types'
import { useAuth } from '../auth/useAuth'
import { describeError } from '../hooks/useAsync'
import { useNotifications } from '../hooks/useNotifications'
import { HealthBadge } from './HealthBadge'
import { NotificationBell } from './NotificationBell'

interface Props {
  workspace: Workspace | null
  channels: Channel[]
  loading: boolean
  error: string | null
  onChannelCreated: () => void
}

export function ChannelSidebar({ workspace, channels, loading, error: loadError, onChannelCreated }: Props) {
  const { user, logout } = useAuth()
  const navigate = useNavigate()
  const notifications = useNotifications(user?.id)
  const [name, setName] = useState('')
  const [type, setType] = useState<ChannelType>('public')
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)

  const create = async (event: FormEvent) => {
    event.preventDefault()

    if (workspace === null) return

    setError(null)

    try {
      await api.createChannel(workspace.id, name, type)
      setName('')
      setOpen(false)
      onChannelCreated()
    } catch (caught) {
      setError(describeError(caught))
    }
  }

  return (
    <aside className="channel-sidebar">
      <header className="channel-sidebar__header">
        <h2>{workspace?.name ?? 'No workspace'}</h2>
      </header>

      <div className="channel-sidebar__scroll">
        <div className="channel-group-label">
          <span>Channels</span>
          <button
            type="button"
            className="icon"
            aria-label="Create a channel"
            title="Create a channel"
            onClick={() => setOpen(!open)}
            disabled={workspace === null}
          >
            +
          </button>
        </div>

        {open && (
          <form className="inline-form" onSubmit={(event) => void create(event)}>
            <input
              type="text"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="channel-name"
              autoFocus
              required
            />
            <select value={type} onChange={(event) => setType(event.target.value as ChannelType)}>
              <option value="public">public</option>
              <option value="private">private</option>
            </select>
            {error !== null && (
              <p className="form-error" role="alert">
                {error}
              </p>
            )}
            <button type="submit" className="primary">
              Create channel
            </button>
          </form>
        )}

        {loading && <p className="muted">Loading channels…</p>}

        {loadError !== null && (
          <p className="form-error" role="alert">
            {loadError}
          </p>
        )}

        {!loading && loadError === null && channels.length === 0 && (
          <p className="muted">No channels yet. Create the first one.</p>
        )}

        <ul className="channel-list">
          {channels.map((channel) => (
            <li key={channel.id}>
              <NavLink
                to={`/workspaces/${channel.workspace_id}/channels/${channel.id}`}
                className={({ isActive }) => `channel-link${isActive ? ' channel-link--active' : ''}`}
              >
                <span className="channel-sigil" aria-hidden="true">
                  {channel.type === 'private' ? '🔒' : '#'}
                </span>
                {channel.name}
              </NavLink>
            </li>
          ))}
        </ul>
      </div>

      <footer className="channel-sidebar__footer">
        <div>
          <strong>{user?.name}</strong>
          <span className="muted">{user?.email}</span>
        </div>
        <NotificationBell
          notifications={notifications.notifications}
          unreadCount={notifications.unreadCount}
          open={notifications.open}
          onToggle={() => notifications.setOpen((value) => !value)}
          onMarkRead={(id) => void notifications.markRead(id)}
          onMarkAllRead={() => void notifications.markAllRead()}
          onOpenChannel={(channelId) => {
            notifications.setOpen(false)
            if (workspace !== null) {
              void navigate(`/workspaces/${workspace.id}/channels/${channelId}`)
            }
          }}
        />
        <HealthBadge />
        <button type="button" className="link" onClick={logout}>
          Sign out
        </button>
      </footer>
    </aside>
  )
}
