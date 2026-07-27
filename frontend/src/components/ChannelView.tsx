import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { api } from '../api/client'
import type { Message, ReactionSummary } from '../api/types'
import { useAuth } from '../auth/useAuth'
import { describeError, useAsync } from '../hooks/useAsync'
import { useChannelRealtime } from '../realtime/useChannelRealtime'
import { MessageComposer } from './MessageComposer'
import { MessageList } from './MessageList'
import { PresenceList } from './PresenceList'
import { TypingIndicator } from './TypingIndicator'
import { useShell } from './shellContext'

export function ChannelView() {
  const { channelId } = useParams<{ channelId: string }>()
  const { channels } = useShell()
  const { user } = useAuth()
  const channel = channels.find((candidate) => candidate.id === channelId) ?? null

  const loadMessages = useCallback(
    () => (channelId === undefined ? Promise.resolve([]) : api.listMessages(channelId)),
    [channelId],
  )

  const loadMembers = useCallback(
    () => (channelId === undefined ? Promise.resolve([]) : api.listChannelMembers(channelId)),
    [channelId],
  )

  const messages = useAsync(loadMessages)
  const members = useAsync(loadMembers)
  const setMessages = messages.setData
  const [actionError, setActionError] = useState<string | null>(null)
  const [threadRoot, setThreadRoot] = useState<Message | null>(null)
  const [threadReplies, setThreadReplies] = useState<Message[]>([])

  const appendMessage = useCallback(
    (message: Message) => {
      if (message.thread_root_id !== null) {
        setThreadReplies((current) =>
          current.some((candidate) => candidate.id === message.id)
            ? current
            : [...current, message],
        )
        setMessages((current) =>
          (current ?? []).map((candidate) =>
            candidate.id === message.thread_root_id
              ? {
                  ...candidate,
                  reply_count: candidate.reply_count + 1,
                  last_reply_at: message.inserted_at,
                }
              : candidate,
          ),
        )
        return
      }

      setMessages((current) => {
        const existing = current ?? []

        return existing.some((candidate) => candidate.id === message.id)
          ? existing
          : [...existing, normalizeMessage(message)]
      })
    },
    [setMessages],
  )

  const applyReactions = useCallback(
    (messageId: string, reactions: ReactionSummary[]) => {
      setMessages((current) =>
        (current ?? []).map((candidate) =>
          candidate.id === messageId ? { ...candidate, reactions } : candidate,
        ),
      )
      setThreadReplies((current) =>
        current.map((candidate) =>
          candidate.id === messageId ? { ...candidate, reactions } : candidate,
        ),
      )
      setThreadRoot((current) =>
        current?.id === messageId ? { ...current, reactions } : current,
      )
    },
    [setMessages],
  )

  const onThreadReplyMeta = useCallback(
    (payload: {
      reply: Message
      thread_root_id: string
      reply_count: number
      last_reply_at: string
    }) => {
      appendMessage(normalizeMessage(payload.reply))
      setMessages((current) =>
        (current ?? []).map((candidate) =>
          candidate.id === payload.thread_root_id
            ? {
                ...candidate,
                reply_count: payload.reply_count,
                last_reply_at: payload.last_reply_at,
              }
            : candidate,
        ),
      )
    },
    [appendMessage, setMessages],
  )

  const realtime = useChannelRealtime(channelId, appendMessage, applyReactions, onThreadReplyMeta)

  useEffect(() => {
    setActionError(null)
    setThreadRoot(null)
    setThreadReplies([])
  }, [channelId])

  const isMember =
    members.data !== null && user !== null
      ? members.data.some((member) => member.user_id === user.id)
      : false

  const openThread = async (message: Message) => {
    setThreadRoot(message)
    const thread = await api.listThread(message.id)
    setThreadRoot(normalizeMessage(thread[0] ?? message))
    setThreadReplies(thread.slice(1).map(normalizeMessage))
  }

  const send = async (body: string) => {
    if (channelId === undefined) return

    setActionError(null)

    try {
      if (threadRoot !== null) {
        appendMessage(await api.sendMessage(channelId, body, threadRoot.id))
        return
      }

      appendMessage(await realtime.pushMessage(body))
    } catch {
      try {
        appendMessage(
          await api.sendMessage(
            channelId,
            body,
            threadRoot !== null ? threadRoot.id : undefined,
          ),
        )
      } catch (caught) {
        setActionError(describeError(caught))
      }
    }
  }

  const join = async () => {
    if (channelId === undefined) return

    setActionError(null)

    try {
      await api.joinChannel(channelId)
      members.reload()
      messages.reload()
    } catch (caught) {
      setActionError(describeError(caught))
    }
  }

  if (channelId === undefined) {
    return (
      <section className="channel-view channel-view--empty">
        <div>
          <h2>Pick a channel</h2>
          <p className="muted">
            Message history is durable state in PostgreSQL. Presence and typing indicators are
            not, and disappear with the processes that hold them.
          </p>
        </div>
      </section>
    )
  }

  const unreadable = messages.error !== null && messages.data === null

  return (
    <section className={`channel-view${threadRoot ? ' channel-view--threaded' : ''}`}>
      <div className="channel-view__main">
        <header className="channel-header">
          <h2>
            <span aria-hidden="true">{channel?.type === 'private' ? '🔒' : '#'}</span>
            {channel?.name ?? 'channel'}
          </h2>
          <div className="channel-header__meta">
            <PresenceList users={realtime.presentUsers} />
            {members.data !== null && (
              <span className="muted">
                {members.data.length} member{members.data.length === 1 ? '' : 's'}
              </span>
            )}
          </div>
        </header>

        {realtime.status === 'unavailable' && (
          <p className="realtime-banner" role="status">
            Realtime is unavailable, so messages are being sent over HTTP. Labs 02, 04 and 05
            implement the channel handlers.
          </p>
        )}

        {messages.loading && <p className="muted pad">Loading history…</p>}

        {unreadable && (
          <div className="notice">
            <p>{messages.error}</p>
            <button type="button" className="primary" onClick={() => void join()}>
              Try joining this channel
            </button>
          </div>
        )}

        {messages.data !== null && (
          <MessageList
            messages={messages.data.map(normalizeMessage)}
            onOpenThread={(message) => void openThread(message)}
            onReactionsChanged={applyReactions}
          />
        )}

        {!isMember && members.data !== null && (
          <div className="notice notice--inline">
            <p>You can read this channel as a workspace member. Join it to post.</p>
            <button type="button" className="primary" onClick={() => void join()}>
              Join #{channel?.name}
            </button>
          </div>
        )}

        {actionError !== null && (
          <p className="form-error pad" role="alert">
            {actionError}
          </p>
        )}

        {threadRoot === null && (
          <div className="channel-view__footer">
            <TypingIndicator users={realtime.typingUsers} />
            <MessageComposer
              channelName={channel?.name ?? 'channel'}
              disabled={!isMember}
              onSend={send}
              onTyping={realtime.notifyTyping}
            />
          </div>
        )}
      </div>

      {threadRoot !== null && (
        <aside className="thread-pane" aria-label="Thread">
          <header>
            <h3>Thread</h3>
            <button type="button" onClick={() => setThreadRoot(null)} aria-label="Close thread">
              Close
            </button>
          </header>
          <MessageList
            messages={[threadRoot, ...threadReplies]}
            onReactionsChanged={applyReactions}
          />
          <MessageComposer
            channelName="thread"
            disabled={!isMember}
            onSend={send}
            onTyping={realtime.notifyTyping}
          />
        </aside>
      )}
    </section>
  )
}

function normalizeMessage(message: Message): Message {
  return {
    ...message,
    thread_root_id: message.thread_root_id ?? null,
    reply_count: message.reply_count ?? 0,
    last_reply_at: message.last_reply_at ?? null,
    reactions: message.reactions ?? [],
    mention_user_ids: message.mention_user_ids ?? [],
  }
}
