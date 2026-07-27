import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError, api, getAuthToken, setAuthToken } from './client'

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

describe('api client', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
    setAuthToken(null)
    localStorage.clear()
  })

  it('unwraps the data envelope', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse({ data: [{ id: 'w1' }] }))

    await expect(api.listWorkspaces()).resolves.toEqual([{ id: 'w1' }])
  })

  it('sends the bearer token once one is set', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(jsonResponse({ data: { id: 'u1' } }))

    setAuthToken('token-abc')
    await api.me()

    const headers = (fetchSpy.mock.calls[0]?.[1]?.headers ?? new Headers()) as Headers
    expect(headers.get('authorization')).toBe('Bearer token-abc')
  })

  it('sends no authorization header when unauthenticated', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(jsonResponse({ data: { token: 't', user: { id: 'u1' } } }))

    await api.login({ email: 'a@example.com', password: 'password123' })

    const headers = (fetchSpy.mock.calls[0]?.[1]?.headers ?? new Headers()) as Headers
    expect(headers.get('authorization')).toBeNull()
  })

  it('persists and restores the token', () => {
    setAuthToken('token-xyz')
    expect(localStorage.getItem('beamslack.token')).toBe('token-xyz')

    setAuthToken(null)
    expect(getAuthToken()).toBeNull()
  })

  it('turns changeset errors into field errors', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      jsonResponse({ errors: { email: ['has already been taken'] } }, 422),
    )

    const failure = await api
      .register({ name: 'a', email: 'a@example.com', password: 'password123' })
      .catch((error: unknown) => error)

    expect(failure).toBeInstanceOf(ApiError)
    expect((failure as ApiError).status).toBe(422)
    expect((failure as ApiError).fieldErrors.email).toEqual(['has already been taken'])
    expect((failure as ApiError).detail).toBe('email has already been taken')
  })

  it('reports a forbidden response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      jsonResponse({ errors: { detail: 'Forbidden' } }, 403),
    )

    const failure = await api.listMessages('channel-1').catch((error: unknown) => error)

    expect((failure as ApiError).status).toBe(403)
    expect((failure as ApiError).message).toBe('Forbidden')
  })

  it('reports an unreachable backend', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'))

    const failure = await api.listWorkspaces().catch((error: unknown) => error)

    expect((failure as ApiError).status).toBe(0)
  })

  it('reports health', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse({ status: 'ok' }))
    await expect(api.health()).resolves.toMatchObject({ up: true })

    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'))
    await expect(api.health()).resolves.toMatchObject({ up: false })
  })

  it('reports which node answered, and who it is clustered with', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      jsonResponse({ status: 'ok', node: 'beamslack_a@host', connected_nodes: ['beamslack_b@host'] }),
    )

    await expect(api.health()).resolves.toEqual({
      up: true,
      node: 'beamslack_a@host',
      connectedNodes: ['beamslack_b@host'],
    })
  })

  it('caps and forwards the message limit', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(jsonResponse({ data: [] }))

    await api.listMessages('channel-1', 25)

    expect(fetchSpy.mock.calls[0]?.[0]).toBe('/api/channels/channel-1/messages?limit=25')
  })
})
