export interface User {
  id: string
  name: string
  email: string
  inserted_at: string
}

export interface Workspace {
  id: string
  name: string
  owner_id: string
  inserted_at: string
}

export type WorkspaceRole = 'owner' | 'admin' | 'member'

export interface WorkspaceMember {
  workspace_id: string
  user_id: string
  role: WorkspaceRole
  joined_at: string
  user: User | null
}

export type ChannelType = 'public' | 'private'

export interface Channel {
  id: string
  workspace_id: string
  name: string
  type: ChannelType
  inserted_at: string
}

export interface ChannelMember {
  channel_id: string
  user_id: string
  joined_at: string
  user: User | null
}

export interface Message {
  id: string
  channel_id: string
  sender_id: string
  body: string
  thread_root_id: string | null
  reply_count: number
  last_reply_at: string | null
  inserted_at: string
  sender: User | null
  reactions: ReactionSummary[]
  mention_user_ids: string[]
}

export interface ReactionSummary {
  emoji: string
  count: number
  user_ids: string[]
  reacted: boolean
}

export interface Notification {
  id: string
  user_id: string
  message_id: string
  channel_id: string
  kind: 'mention' | 'thread_reply'
  read_at: string | null
  inserted_at: string
  message: {
    id: string
    body: string
    sender: User | null
  } | null
}

export interface Session {
  token: string
  user: User
}

/** Field name to list of messages, as rendered by BeamSlackWeb.ChangesetJSON. */
export type FieldErrors = Record<string, string[]>

export const REACTION_EMOJIS = ['👍', '👎', '❤️', '🎉', '😄', '😕', '🚀', '👀', '🔥', '✅'] as const
