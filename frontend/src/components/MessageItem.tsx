import { useState } from 'react'
import { api } from '../api/client'
import type { Message, ReactionSummary } from '../api/types'
import { REACTION_EMOJIS } from '../api/types'

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

function highlightMentions(body: string) {
  const parts = body.split(/(@[a-zA-Z0-9_\-.]+)/g)

  return parts.map((part, index) =>
    part.startsWith('@') ? (
      <span key={`${part}-${index}`} className="mention">
        {part}
      </span>
    ) : (
      part
    ),
  )
}

export function MessageItem({
  message,
  grouped,
  onOpenThread,
  onReactionsChanged,
}: {
  message: Message
  grouped: boolean
  onOpenThread?: (message: Message) => void
  onReactionsChanged: (messageId: string, reactions: ReactionSummary[]) => void
}) {
  const [pickerOpen, setPickerOpen] = useState(false)

  const toggleReaction = async (emoji: string) => {
    const existing = message.reactions.find((reaction) => reaction.emoji === emoji)
    const reactions =
      existing?.reacted === true
        ? await api.removeReaction(message.id, emoji)
        : await api.addReaction(message.id, emoji)

    onReactionsChanged(message.id, reactions)
    setPickerOpen(false)
  }

  return (
    <article className={`message${grouped ? ' message--grouped' : ''}`}>
      {!grouped && (
        <header>
          <strong>{message.sender?.name ?? 'unknown'}</strong>
          <time dateTime={message.inserted_at}>{formatTime(message.inserted_at)}</time>
        </header>
      )}
      <p>{highlightMentions(message.body)}</p>

      <div className="message__meta">
        <div className="reactions">
          {message.reactions.map((reaction) => (
            <button
              key={reaction.emoji}
              type="button"
              className={`reaction${reaction.reacted ? ' reaction--mine' : ''}`}
              onClick={() => void toggleReaction(reaction.emoji)}
            >
              {reaction.emoji} {reaction.count}
            </button>
          ))}
          <button
            type="button"
            className="reaction reaction--add"
            aria-label="Add reaction"
            onClick={() => setPickerOpen((open) => !open)}
          >
            +
          </button>
          {pickerOpen && (
            <div className="reaction-picker" role="listbox">
              {REACTION_EMOJIS.map((emoji) => (
                <button key={emoji} type="button" onClick={() => void toggleReaction(emoji)}>
                  {emoji}
                </button>
              ))}
            </div>
          )}
        </div>

        {onOpenThread && message.thread_root_id === null && (
          <button type="button" className="thread-link" onClick={() => onOpenThread(message)}>
            {message.reply_count > 0
              ? `${message.reply_count} ${message.reply_count === 1 ? 'reply' : 'replies'}`
              : 'Reply in thread'}
          </button>
        )}
      </div>
    </article>
  )
}
