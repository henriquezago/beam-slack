import { render } from '@testing-library/react'
import type { ReactElement } from 'react'
import { MemoryRouter } from 'react-router-dom'
import { vi } from 'vitest'
import { AuthProvider } from '../auth/AuthContext'

/** A route table keyed by `"METHOD /api/path"`, matched exactly ignoring query. */
export type Routes = Record<string, unknown>

/**
 * Installs a `fetch` stub that answers from `routes`. Unmatched requests resolve
 * to 404 so a missing route shows up as a visible failure rather than a hang.
 */
export function mockFetch(routes: Routes) {
  return vi.spyOn(globalThis, 'fetch').mockImplementation((input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    const method = (init?.method ?? 'GET').toUpperCase()
    const path = url.replace(/^https?:\/\/[^/]+/, '').split('?')[0]

    const key = `${method} ${path ?? ''}`

    if (!(key in routes)) {
      return Promise.resolve(
        new Response(JSON.stringify({ errors: { detail: 'Not Found' } }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        }),
      )
    }

    return Promise.resolve(
      new Response(JSON.stringify(routes[key]), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    )
  })
}

export function renderWithProviders(ui: ReactElement, initialPath = '/') {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <AuthProvider>{ui}</AuthProvider>
    </MemoryRouter>,
  )
}

export const fixtures = {
  user: {
    id: 'user-1',
    name: 'henrique',
    email: 'henrique@example.com',
    inserted_at: '2026-07-01T10:00:00Z',
  },
  workspace: {
    id: 'workspace-1',
    name: 'beam-crew',
    owner_id: 'user-1',
    inserted_at: '2026-07-01T10:00:00Z',
  },
  channel: {
    id: 'channel-1',
    workspace_id: 'workspace-1',
    name: 'general',
    type: 'public' as const,
    inserted_at: '2026-07-01T10:00:00Z',
  },
  privateChannel: {
    id: 'channel-2',
    workspace_id: 'workspace-1',
    name: 'leadership',
    type: 'private' as const,
    inserted_at: '2026-07-01T10:00:00Z',
  },
}
