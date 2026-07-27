import { useState, type FormEvent, type KeyboardEvent } from 'react'

interface Props {
  channelName: string
  disabled: boolean
  onSend: (body: string) => Promise<void>
  /** Called on each keystroke. Throttling is the server's problem, in Lab 05. */
  onTyping?: () => void
}

export function MessageComposer({ channelName, disabled, onSend, onTyping }: Props) {
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)

  const submit = async (event: FormEvent) => {
    event.preventDefault()

    const trimmed = body.trim()
    if (trimmed === '' || sending) return

    setSending(true)

    try {
      await onSend(trimmed)
      setBody('')
    } finally {
      setSending(false)
    }
  }

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      void submit(event)
    }
  }

  return (
    <form className="composer" onSubmit={(event) => void submit(event)}>
      <textarea
        value={body}
        onChange={(event) => {
          setBody(event.target.value)
          if (event.target.value !== '') onTyping?.()
        }}
        onKeyDown={onKeyDown}
        placeholder={disabled ? 'Join the channel to post' : `Message #${channelName}`}
        aria-label={`Message #${channelName}`}
        rows={1}
        disabled={disabled || sending}
      />
      <button type="submit" className="primary" disabled={disabled || sending || body.trim() === ''}>
        Send
      </button>
    </form>
  )
}
