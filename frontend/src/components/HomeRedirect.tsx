import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../api/client'
import { useAuth } from '../auth/useAuth'
import { describeError, useAsync } from '../hooks/useAsync'
import { HealthBadge } from './HealthBadge'

/**
 * Landing route. Sends the user to their first workspace, or asks them to create
 * one when they have none.
 */
export function HomeRedirect() {
  const navigate = useNavigate()
  const { logout } = useAuth()
  const workspaces = useAsync(useCallback(() => api.listWorkspaces(), []))
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)

  const first = workspaces.data?.[0]

  useEffect(() => {
    if (first !== undefined) void navigate(`/workspaces/${first.id}`, { replace: true })
  }, [first, navigate])

  const create = async (event: FormEvent) => {
    event.preventDefault()
    setError(null)

    try {
      const workspace = await api.createWorkspace(name)
      void navigate(`/workspaces/${workspace.id}`, { replace: true })
    } catch (caught) {
      setError(describeError(caught))
    }
  }

  if (workspaces.loading) {
    return (
      <div className="auth-screen">
        <p className="muted">Loading workspaces…</p>
      </div>
    )
  }

  if (first !== undefined) return null

  return (
    <div className="auth-screen">
      <form className="auth-card" onSubmit={(event) => void create(event)}>
        <p className="eyebrow">First run</p>
        <h1>Create a workspace</h1>
        <p className="intro">
          You do not belong to any workspace yet. Create one, or run{' '}
          <code>mix run priv/repo/seeds.exs</code> and sign in as a seeded user.
        </p>

        <label>
          Workspace name
          <input
            type="text"
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="beam-crew"
            required
          />
        </label>

        {(error ?? workspaces.error) !== null && (
          <p className="form-error" role="alert">
            {error ?? workspaces.error}
          </p>
        )}

        <button type="submit" className="primary">
          Create workspace
        </button>

        <button type="button" className="link" onClick={logout}>
          Sign out
        </button>

        <footer className="auth-card__footer">
          <HealthBadge />
        </footer>
      </form>
    </div>
  )
}
