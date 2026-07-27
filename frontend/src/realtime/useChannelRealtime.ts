import { Presence, type Channel } from 'phoenix'
import { useCallback, useEffect, useRef, useState } from 'react'
import type { Message, ReactionSummary } from '../api/types'
import { getSocket } from './socket'

export type RealtimeStatus = 'disconnected' | 'joining' | 'joined' | 'unavailable'

export interface PresentUser {
  id: string
  name: string
  /** One user can be present from several tabs or devices. */
  deviceCount: number
}

export interface TypingUser {
  user_id: string
  name: string
}

interface PresenceMeta {
  name?: string
  phx_ref: string
}

export interface ThreadReplyPayload {
  reply: Message
  thread_root_id: string
  reply_count: number
  last_reply_at: string
}

const PUSH_TIMEOUT_MS = 3_000

/**
 * Joins `channel:<channelId>` and surfaces what the server broadcasts.
 *
 * Until Labs 02, 04, and 05 are implemented, joining succeeds but the message,
 * presence, and typing handlers raise on the server. The channel process crashes,
 * `onError` fires, and this hook reports `unavailable` so the UI can fall back to
 * plain HTTP instead of appearing broken.
 *
 * Reaction and thread events from Track 5 are handled here regardless: they are
 * published by the REST path via PubSub, not by the Lab 02 handler.
 */
export function useChannelRealtime(
  channelId: string | undefined,
  onMessage: (message: Message) => void,
  onReactionsChanged?: (messageId: string, reactions: ReactionSummary[]) => void,
  onThreadReply?: (payload: ThreadReplyPayload) => void,
) {
  const [status, setStatus] = useState<RealtimeStatus>('disconnected')
  const [presentUsers, setPresentUsers] = useState<PresentUser[]>([])
  const [typingUsers, setTypingUsers] = useState<TypingUser[]>([])
  const channelRef = useRef<Channel | null>(null)
  const onMessageRef = useRef(onMessage)
  const onReactionsRef = useRef(onReactionsChanged)
  const onThreadRef = useRef(onThreadReply)

  useEffect(() => {
    onMessageRef.current = onMessage
  }, [onMessage])

  useEffect(() => {
    onReactionsRef.current = onReactionsChanged
  }, [onReactionsChanged])

  useEffect(() => {
    onThreadRef.current = onThreadReply
  }, [onThreadReply])

  useEffect(() => {
    if (channelId === undefined) return

    const socket = getSocket()
    if (socket === null) return

    const channel = socket.channel(`channel:${channelId}`, {})
    channelRef.current = channel
    setStatus('joining')

    const presence = new Presence(channel)

    presence.onSync(() => {
      setPresentUsers(
        presence.list((id, presenceEntry) => {
          const metas = (presenceEntry as { metas: PresenceMeta[] }).metas

          return { id, name: metas[0]?.name ?? id, deviceCount: metas.length }
        }),
      )
    })

    channel.on('new_message', (payload) => {
      onMessageRef.current(payload as Message)
    })

    channel.on('reactions_changed', (payload) => {
      const data = payload as { message_id: string; reactions: ReactionSummary[] }
      onReactionsRef.current?.(data.message_id, data.reactions)
    })

    channel.on('thread_reply', (payload) => {
      onThreadRef.current?.(payload as ThreadReplyPayload)
    })

    channel.on('typing_started', (payload) => {
      const typing = payload as TypingUser

      setTypingUsers((current) =>
        current.some((candidate) => candidate.user_id === typing.user_id)
          ? current
          : [...current, typing],
      )
    })

    channel.on('typing_stopped', (payload) => {
      const { user_id } = payload as { user_id: string }

      setTypingUsers((current) => current.filter((candidate) => candidate.user_id !== user_id))
    })

    channel.onError(() => {
      setStatus('unavailable')
      setTypingUsers([])
    })

    channel
      .join()
      .receive('ok', () => setStatus('joined'))
      .receive('error', () => setStatus('unavailable'))
      .receive('timeout', () => setStatus('unavailable'))

    return () => {
      channel.leave()
      channelRef.current = null
      setStatus('disconnected')
      setPresentUsers([])
      setTypingUsers([])
    }
  }, [channelId])

  const pushMessage = useCallback(
    (body: string) =>
      new Promise<Message>((resolve, reject) => {
        const channel = channelRef.current

        if (channel === null || status !== 'joined') {
          reject(new Error('realtime unavailable'))
          return
        }

        channel
          .push('new_message', { body }, PUSH_TIMEOUT_MS)
          .receive('ok', (message) => resolve(message as Message))
          .receive('error', (reason) => {
            reject(new Error(typeof reason === 'string' ? reason : 'push rejected'))
          })
          .receive('timeout', () => {
            setStatus('unavailable')
            reject(new Error('realtime timed out'))
          })
      }),
    [status],
  )

  const notifyTyping = useCallback(() => {
    if (status !== 'joined') return

    channelRef.current?.push('typing', {}, PUSH_TIMEOUT_MS)
  }, [status])

  return { status, presentUsers, typingUsers, pushMessage, notifyTyping }
}
