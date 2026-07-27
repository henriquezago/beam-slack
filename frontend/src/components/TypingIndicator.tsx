import type { TypingUser } from '../realtime/useChannelRealtime'

function describe(users: TypingUser[]): string {
  const names = users.map((user) => user.name)

  if (names.length === 1) return `${names[0]} is typing…`
  if (names.length === 2) return `${names[0]} and ${names[1]} are typing…`
  if (names.length === 3) return `${names[0]}, ${names[1]} and ${names[2]} are typing…`

  return 'Several people are typing…'
}

/**
 * Deliberately ephemeral: nothing here is ever persisted, and it is correct for
 * it to vanish when a process dies.
 */
export function TypingIndicator({ users }: { users: TypingUser[] }) {
  return (
    <p className="typing-indicator" aria-live="polite">
      {users.length === 0 ? '\u00a0' : describe(users)}
    </p>
  )
}
