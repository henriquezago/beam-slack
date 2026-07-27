import { screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'
import { setAuthToken } from './api/client'
import { fixtures, mockFetch, renderWithProviders } from './test/utils'

// jsdom would try to open a real WebSocket. The realtime layer has its own tests.
vi.mock('./realtime/socket', () => ({
  getSocket: () => null,
  disconnectSocket: () => undefined,
}))

describe('App', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
    setAuthToken(null)
    localStorage.clear()
  })

  it('shows the sign-in screen when there is no token', async () => {
    mockFetch({ 'GET /api/health': { status: 'ok' } })

    renderWithProviders(<App />)

    expect(await screen.findByRole('button', { name: 'Sign in' })).toBeInTheDocument()
  })

  it('renders the workspace shell for an authenticated user', async () => {
    setAuthToken('a-valid-token')

    mockFetch({
      'GET /api/health': { status: 'ok' },
      'GET /api/me': { data: fixtures.user },
      'GET /api/workspaces': { data: [fixtures.workspace] },
    })

    renderWithProviders(<App />, `/workspaces/${fixtures.workspace.id}`)

    expect(await screen.findByRole('heading', { name: 'beam-crew' })).toBeInTheDocument()
    expect(await screen.findByText('henrique@example.com')).toBeInTheDocument()
  })

  it('lists the channels of the active workspace', async () => {
    setAuthToken('a-valid-token')

    mockFetch({
      'GET /api/health': { status: 'ok' },
      'GET /api/me': { data: fixtures.user },
      'GET /api/workspaces': { data: [fixtures.workspace] },
      [`GET /api/workspaces/${fixtures.workspace.id}/channels`]: {
        data: [fixtures.channel, fixtures.privateChannel],
      },
      'GET /api/notifications': { data: [] },
      'GET /api/notifications/unread_count': { data: { count: 0 } },
    })

    renderWithProviders(<App />, `/workspaces/${fixtures.workspace.id}`)

    expect(await screen.findByRole('link', { name: /general/ })).toBeInTheDocument()
    expect(await screen.findByRole('link', { name: /leadership/ })).toBeInTheDocument()
  })

  it('shows a channel history and composer', async () => {
    setAuthToken('a-valid-token')

    mockFetch({
      'GET /api/health': { status: 'ok' },
      'GET /api/me': { data: fixtures.user },
      'GET /api/workspaces': { data: [fixtures.workspace] },
      [`GET /api/workspaces/${fixtures.workspace.id}/channels`]: { data: [fixtures.channel] },
      [`GET /api/channels/${fixtures.channel.id}/members`]: {
        data: [
          {
            channel_id: fixtures.channel.id,
            user_id: fixtures.user.id,
            joined_at: '2026-07-01T10:00:00Z',
            user: fixtures.user,
          },
        ],
      },
      [`GET /api/channels/${fixtures.channel.id}/messages`]: {
        data: [
          {
            id: 'message-1',
            channel_id: fixtures.channel.id,
            sender_id: fixtures.user.id,
            body: 'durable state lives in postgres',
            thread_root_id: null,
            reply_count: 0,
            last_reply_at: null,
            inserted_at: '2026-07-01T10:05:00Z',
            sender: fixtures.user,
            reactions: [],
            mention_user_ids: [],
          },
        ],
      },
      'GET /api/notifications': { data: [] },
      'GET /api/notifications/unread_count': { data: { count: 0 } },
    })

    renderWithProviders(
      <App />,
      `/workspaces/${fixtures.workspace.id}/channels/${fixtures.channel.id}`,
    )

    expect(await screen.findByText('durable state lives in postgres')).toBeInTheDocument()

    const composer = await screen.findByRole('textbox', { name: 'Message #general' })
    expect(composer).toBeEnabled()
  })

  it('offers to join a channel the user only reads', async () => {
    setAuthToken('a-valid-token')

    mockFetch({
      'GET /api/health': { status: 'ok' },
      'GET /api/me': { data: fixtures.user },
      'GET /api/workspaces': { data: [fixtures.workspace] },
      [`GET /api/workspaces/${fixtures.workspace.id}/channels`]: { data: [fixtures.channel] },
      [`GET /api/channels/${fixtures.channel.id}/members`]: { data: [] },
      [`GET /api/channels/${fixtures.channel.id}/messages`]: { data: [] },
      'GET /api/notifications': { data: [] },
      'GET /api/notifications/unread_count': { data: { count: 0 } },
    })

    renderWithProviders(
      <App />,
      `/workspaces/${fixtures.workspace.id}/channels/${fixtures.channel.id}`,
    )

    expect(await screen.findByRole('button', { name: 'Join #general' })).toBeInTheDocument()

    const composer = await screen.findByRole('textbox', { name: 'Message #general' })
    expect(composer).toBeDisabled()
  })

  it('asks the user to create a workspace when they have none', async () => {
    setAuthToken('a-valid-token')

    mockFetch({
      'GET /api/health': { status: 'ok' },
      'GET /api/me': { data: fixtures.user },
      'GET /api/workspaces': { data: [] },
    })

    renderWithProviders(<App />)

    expect(await screen.findByRole('heading', { name: 'Create a workspace' })).toBeInTheDocument()
  })

  it('drops an invalid stored token and falls back to sign-in', async () => {
    setAuthToken('an-expired-token')

    mockFetch({ 'GET /api/health': { status: 'ok' } })

    renderWithProviders(<App />)

    expect(await screen.findByRole('button', { name: 'Sign in' })).toBeInTheDocument()
    await waitFor(() => {
      expect(localStorage.getItem('beamslack.token')).toBeNull()
    })
  })
})
