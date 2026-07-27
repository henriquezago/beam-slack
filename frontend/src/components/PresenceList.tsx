import type { PresentUser } from '../realtime/useChannelRealtime'

/**
 * One user can be present several times over, once per tab or device. The
 * backend keeps every meta entry; we surface the count so the multi-device
 * behavior from Lab 04 is visible rather than hidden behind a boolean.
 */
export function PresenceList({ users }: { users: PresentUser[] }) {
  if (users.length === 0) return null

  return (
    <ul className="presence-list" aria-label="Here now">
      {users.map((user) => (
        <li key={user.id} title={`${user.name}, ${user.deviceCount} connection(s)`}>
          <span className="presence-dot" aria-hidden="true" />
          {user.name}
          {user.deviceCount > 1 && <sup>{user.deviceCount}</sup>}
        </li>
      ))}
    </ul>
  )
}
