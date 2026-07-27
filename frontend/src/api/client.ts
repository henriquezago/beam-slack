import type {
  Channel,
  ChannelMember,
  ChannelType,
  FieldErrors,
  Message,
  Notification,
  ReactionSummary,
  Session,
  User,
  Workspace,
  WorkspaceMember,
} from './types'

/**
 * A failed API call. `status` is the HTTP status and `fieldErrors` carries the
 * changeset errors the backend renders for a 422.
 */
export class ApiError extends Error {
  readonly status: number
  readonly fieldErrors: FieldErrors

  constructor(status: number, message: string, fieldErrors: FieldErrors = {}) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.fieldErrors = fieldErrors
  }

  /** "email has already been taken" style summary for display. */
  get detail(): string {
    const entries = Object.entries(this.fieldErrors)

    if (entries.length === 0) return this.message

    return entries
      .map(([field, messages]) => `${field} ${messages.join(', ')}`)
      .join('; ')
  }
}

interface Envelope<T> {
  data: T
}

const TOKEN_STORAGE_KEY = 'beamslack.token'

let authToken: string | null = null

export function setAuthToken(token: string | null): void {
  authToken = token

  try {
    if (token === null) {
      localStorage.removeItem(TOKEN_STORAGE_KEY)
    } else {
      localStorage.setItem(TOKEN_STORAGE_KEY, token)
    }
  } catch {
    // Storage can be unavailable (private mode, test environments). The token
    // still works for the lifetime of this page.
  }
}

export function getAuthToken(): string | null {
  if (authToken !== null) return authToken

  try {
    authToken = localStorage.getItem(TOKEN_STORAGE_KEY)
  } catch {
    authToken = null
  }

  return authToken
}

function statusMessage(status: number): string {
  if (status === 401) return 'Not authenticated'
  if (status === 403) return 'Not allowed'
  if (status === 404) return 'Not found'
  if (status === 422) return 'Validation failed'
  return `Request failed with status ${status}`
}

function parseErrors(body: unknown): { fieldErrors: FieldErrors; detail?: string } {
  if (typeof body !== 'object' || body === null || !('errors' in body)) {
    return { fieldErrors: {} }
  }

  const errors = (body as { errors: unknown }).errors

  if (typeof errors !== 'object' || errors === null) return { fieldErrors: {} }

  if ('detail' in errors && typeof (errors as { detail: unknown }).detail === 'string') {
    return { fieldErrors: {}, detail: (errors as { detail: string }).detail }
  }

  const fieldErrors: FieldErrors = {}

  for (const [field, messages] of Object.entries(errors)) {
    if (Array.isArray(messages)) {
      fieldErrors[field] = messages.map(String)
    }
  }

  return { fieldErrors }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  headers.set('accept', 'application/json')

  if (init.body !== undefined) headers.set('content-type', 'application/json')

  const token = getAuthToken()
  if (token !== null) headers.set('authorization', `Bearer ${token}`)

  let response: Response

  try {
    response = await fetch(`/api${path}`, { ...init, headers })
  } catch {
    throw new ApiError(0, 'The BeamSlack API is unreachable')
  }

  if (response.status === 204) return undefined as T

  const body: unknown = await response.json().catch(() => null)

  if (!response.ok) {
    const { fieldErrors, detail } = parseErrors(body)
    throw new ApiError(response.status, detail ?? statusMessage(response.status), fieldErrors)
  }

  return (body as Envelope<T>).data
}

export interface Credentials {
  email: string
  password: string
}

export interface Registration extends Credentials {
  name: string
}

/**
 * The health check's answer. `node` and `connectedNodes` matter from Track 4 on:
 * with two nodes running, knowing which one this browser session is talking to is
 * the difference between an observation and a guess.
 */
export interface Health {
  up: boolean
  node?: string
  connectedNodes?: string[]
}

export const api = {
  health: async (): Promise<Health> => {
    try {
      const response = await fetch('/api/health', { headers: { accept: 'application/json' } })
      const body: unknown = await response.json()

      if (!response.ok || typeof body !== 'object' || body === null) return { up: false }

      const payload = body as Partial<{ status: string; node: string; connected_nodes: string[] }>

      if (payload.status !== 'ok') return { up: false }

      return {
        up: true,
        node: payload.node,
        connectedNodes: payload.connected_nodes ?? [],
      }
    } catch {
      return { up: false }
    }
  },

  login: (credentials: Credentials): Promise<Session> =>
    request<Session>('/session', { method: 'POST', body: JSON.stringify(credentials) }),

  register: (registration: Registration): Promise<Session> =>
    request<Session>('/users', { method: 'POST', body: JSON.stringify(registration) }),

  me: (): Promise<User> => request<User>('/me'),

  listWorkspaces: (): Promise<Workspace[]> => request<Workspace[]>('/workspaces'),

  createWorkspace: (name: string): Promise<Workspace> =>
    request<Workspace>('/workspaces', { method: 'POST', body: JSON.stringify({ name }) }),

  listWorkspaceMembers: (workspaceId: string): Promise<WorkspaceMember[]> =>
    request<WorkspaceMember[]>(`/workspaces/${workspaceId}/members`),

  listChannels: (workspaceId: string): Promise<Channel[]> =>
    request<Channel[]>(`/workspaces/${workspaceId}/channels`),

  createChannel: (
    workspaceId: string,
    name: string,
    type: ChannelType = 'public',
  ): Promise<Channel> =>
    request<Channel>(`/workspaces/${workspaceId}/channels`, {
      method: 'POST',
      body: JSON.stringify({ name, type }),
    }),

  joinChannel: (channelId: string): Promise<ChannelMember> =>
    request<ChannelMember>(`/channels/${channelId}/join`, { method: 'POST' }),

  listChannelMembers: (channelId: string): Promise<ChannelMember[]> =>
    request<ChannelMember[]>(`/channels/${channelId}/members`),

  listMessages: (channelId: string, limit = 50): Promise<Message[]> =>
    request<Message[]>(`/channels/${channelId}/messages?limit=${limit}`),

  sendMessage: (channelId: string, body: string, threadRootId?: string): Promise<Message> =>
    request<Message>(`/channels/${channelId}/messages`, {
      method: 'POST',
      body: JSON.stringify({
        body,
        ...(threadRootId !== undefined ? { thread_root_id: threadRootId } : {}),
      }),
    }),

  listThread: (messageId: string): Promise<Message[]> =>
    request<Message[]>(`/messages/${messageId}/thread`),

  addReaction: (messageId: string, emoji: string): Promise<ReactionSummary[]> =>
    request<ReactionSummary[]>(`/messages/${messageId}/reactions`, {
      method: 'POST',
      body: JSON.stringify({ emoji }),
    }),

  removeReaction: (messageId: string, emoji: string): Promise<ReactionSummary[]> =>
    request<ReactionSummary[]>(
      `/messages/${messageId}/reactions?emoji=${encodeURIComponent(emoji)}`,
      { method: 'DELETE' },
    ),

  listNotifications: (): Promise<Notification[]> => request<Notification[]>('/notifications'),

  unreadNotificationCount: (): Promise<{ count: number }> =>
    request<{ count: number }>('/notifications/unread_count'),

  markNotificationRead: (id: string): Promise<Notification> =>
    request<Notification>(`/notifications/${id}/read`, { method: 'POST' }),

  markAllNotificationsRead: (): Promise<void> =>
    request<void>('/notifications/read_all', { method: 'POST' }),
}
