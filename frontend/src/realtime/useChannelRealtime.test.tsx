import { act, renderHook, waitFor } from '@testing-library/react'
import type { Channel, Socket } from 'phoenix'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Message } from '../api/types'
import { useChannelRealtime } from './useChannelRealtime'

type Status = 'ok' | 'error' | 'timeout'

interface Reply {
  receive: (status: string, callback: (response?: unknown) => void) => Reply
}

function reply(status: Status, response?: unknown): Reply {
  const chainable: Reply = {
    receive: (candidate, callback) => {
      if (candidate === status) callback(response)
      return chainable
    },
  }

  return chainable
}

class FakeChannel {
  readonly handlers = new Map<string, (payload: unknown) => void>()
  readonly pushes: { event: string; payload: unknown }[] = []
  left = false
  joinStatus: Status = 'ok'
  pushStatus: Status = 'ok'
  pushResponse: unknown = undefined

  private onErrorCallback: (() => void) | null = null

  on(event: string, callback: (payload: unknown) => void) {
    this.handlers.set(event, callback)
    return 0
  }

  onError(callback: () => void) {
    this.onErrorCallback = callback
  }

  onClose() {}

  /** Phoenix's Presence uses this to discard state from a previous join. */
  joinRef() {
    return '1'
  }

  join() {
    return reply(this.joinStatus)
  }

  push(event: string, payload: unknown) {
    this.pushes.push({ event, payload })
    return reply(this.pushStatus, this.pushResponse)
  }

  leave() {
    this.left = true
    return reply('ok')
  }

  trigger(event: string, payload: unknown) {
    this.handlers.get(event)?.(payload)
  }

  fail() {
    this.onErrorCallback?.()
  }
}

let channel: FakeChannel
let topics: string[]

vi.mock('./socket', () => ({
  getSocket: () => socketStub,
  disconnectSocket: () => undefined,
}))

const socketStub = {
  channel: (topic: string) => {
    topics.push(topic)
    return channel as unknown as Channel
  },
} as unknown as Socket

const message: Message = {
  id: 'message-1',
  channel_id: 'channel-1',
  sender_id: 'user-1',
  body: 'hello from the socket',
  thread_root_id: null,
  reply_count: 0,
  last_reply_at: null,
  inserted_at: '2026-07-01T10:00:00Z',
  sender: { id: 'user-1', name: 'alice', email: 'a@example.com', inserted_at: '2026-07-01T10:00:00Z' },
  reactions: [],
  mention_user_ids: [],
}

function setup(onMessage: (message: Message) => void = () => undefined) {
  return renderHook(() => useChannelRealtime('channel-1', onMessage))
}

describe('useChannelRealtime', () => {
  beforeEach(() => {
    channel = new FakeChannel()
    topics = []
  })

  it('joins the channel topic', async () => {
    const { result } = setup()

    await waitFor(() => expect(result.current.status).toBe('joined'))
    expect(topics).toEqual(['channel:channel-1'])
  })

  it('does nothing without a channel id', () => {
    const { result } = renderHook(() => useChannelRealtime(undefined, () => undefined))

    expect(result.current.status).toBe('disconnected')
    expect(topics).toEqual([])
  })

  it('reports unavailable when the join is rejected', async () => {
    channel.joinStatus = 'error'

    const { result } = setup()

    await waitFor(() => expect(result.current.status).toBe('unavailable'))
  })

  it('reports unavailable when the channel process crashes', async () => {
    const { result } = setup()
    await waitFor(() => expect(result.current.status).toBe('joined'))

    act(() => channel.fail())

    expect(result.current.status).toBe('unavailable')
  })

  it('forwards broadcast messages', async () => {
    const received: Message[] = []
    setup((incoming) => received.push(incoming))

    await waitFor(() => expect(channel.handlers.has('new_message')).toBe(true))
    act(() => channel.trigger('new_message', message))

    expect(received).toEqual([message])
  })

  it('tracks typing users until they stop', async () => {
    const { result } = setup()
    await waitFor(() => expect(result.current.status).toBe('joined'))

    act(() => channel.trigger('typing_started', { user_id: 'user-2', name: 'bob' }))
    expect(result.current.typingUsers).toEqual([{ user_id: 'user-2', name: 'bob' }])

    // A repeat keystroke must not duplicate the entry.
    act(() => channel.trigger('typing_started', { user_id: 'user-2', name: 'bob' }))
    expect(result.current.typingUsers).toHaveLength(1)

    act(() => channel.trigger('typing_stopped', { user_id: 'user-2' }))
    expect(result.current.typingUsers).toEqual([])
  })

  it('surfaces presence, counting several connections from one user once', async () => {
    const { result } = setup()
    await waitFor(() => expect(result.current.status).toBe('joined'))

    act(() =>
      channel.trigger('presence_state', {
        'user-2': { metas: [{ name: 'bob', phx_ref: 'r1' }, { name: 'bob', phx_ref: 'r2' }] },
      }),
    )

    expect(result.current.presentUsers).toEqual([{ id: 'user-2', name: 'bob', deviceCount: 2 }])
  })

  it('pushes a message and resolves with the server reply', async () => {
    channel.pushResponse = message

    const { result } = setup()
    await waitFor(() => expect(result.current.status).toBe('joined'))

    await expect(result.current.pushMessage('hello from the socket')).resolves.toEqual(message)
    expect(channel.pushes).toEqual([
      { event: 'new_message', payload: { body: 'hello from the socket' } },
    ])
  })

  it('rejects a push the server refuses, so the caller can fall back to HTTP', async () => {
    channel.pushStatus = 'error'

    const { result } = setup()
    await waitFor(() => expect(result.current.status).toBe('joined'))

    await expect(result.current.pushMessage('nope')).rejects.toThrow()
  })

  it('rejects a push before the channel has joined', async () => {
    channel.joinStatus = 'timeout'

    const { result } = setup()
    await waitFor(() => expect(result.current.status).toBe('unavailable'))

    await expect(result.current.pushMessage('nope')).rejects.toThrow('realtime unavailable')
    expect(channel.pushes).toEqual([])
  })

  it('sends typing notifications only while joined', async () => {
    const { result } = setup()
    await waitFor(() => expect(result.current.status).toBe('joined'))

    act(() => result.current.notifyTyping())

    expect(channel.pushes).toEqual([{ event: 'typing', payload: {} }])
  })

  it('leaves the channel on unmount', async () => {
    const { result, unmount } = setup()
    await waitFor(() => expect(result.current.status).toBe('joined'))

    unmount()

    expect(channel.left).toBe(true)
  })
})
