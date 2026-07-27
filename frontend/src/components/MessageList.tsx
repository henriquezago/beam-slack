import { useEffect, useRef } from 'react'
import type { Message, ReactionSummary } from '../api/types'
import { MessageItem } from './MessageItem'

function formatDay(iso: string): string {
  return new Date(iso).toLocaleDateString([], {
    weekday: 'long',
    month: 'short',
    day: 'numeric',
  })
}

export function MessageList({
  messages,
  onOpenThread,
  onReactionsChanged,
}: {
  messages: Message[]
  onOpenThread?: (message: Message) => void
  onReactionsChanged: (messageId: string, reactions: ReactionSummary[]) => void
}) {
  const bottom = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottom.current?.scrollIntoView?.({ block: 'end' })
  }, [messages])

  let lastDay: string | null = null
  let lastSender: string | null = null

  return (
    <div className="message-list" role="log" aria-label="Messages">
      {messages.map((message) => {
        const day = formatDay(message.inserted_at)
        const newDay = day !== lastDay
        const grouped = !newDay && message.sender_id === lastSender

        lastDay = day
        lastSender = message.sender_id

        return (
          <div key={message.id}>
            {newDay && (
              <div className="day-divider">
                <span>{day}</span>
              </div>
            )}
            <MessageItem
              message={message}
              grouped={grouped}
              onOpenThread={onOpenThread}
              onReactionsChanged={onReactionsChanged}
            />
          </div>
        )
      })}
      <div ref={bottom} />
    </div>
  )
}
