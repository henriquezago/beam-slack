import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../api/client'
import type { Workspace } from '../api/types'
import { describeError } from '../hooks/useAsync'

interface Props {
  workspaces: Workspace[]
  activeWorkspaceId: string | undefined
  onCreated: () => void
}

function initials(name: string): string {
  return name
    .split(/[\s-_]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('')
}

export function WorkspaceRail({ workspaces, activeWorkspaceId, onCreated }: Props) {
  const navigate = useNavigate()
  const [creating, setCreating] = useState(false)
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)

  const create = async (event: FormEvent) => {
    event.preventDefault()
    setError(null)

    try {
      const workspace = await api.createWorkspace(name)
      setName('')
      setCreating(false)
      onCreated()
      void navigate(`/workspaces/${workspace.id}`)
    } catch (caught) {
      setError(describeError(caught))
    }
  }

  return (
    <nav className="workspace-rail" aria-label="Workspaces">
      {workspaces.map((workspace) => (
        <button
          key={workspace.id}
          type="button"
          className={`workspace-chip${workspace.id === activeWorkspaceId ? ' workspace-chip--active' : ''}`}
          title={workspace.name}
          aria-current={workspace.id === activeWorkspaceId}
          onClick={() => void navigate(`/workspaces/${workspace.id}`)}
        >
          {initials(workspace.name)}
        </button>
      ))}

      <button
        type="button"
        className="workspace-chip workspace-chip--add"
        title="Create a workspace"
        aria-label="Create a workspace"
        onClick={() => setCreating(!creating)}
      >
        +
      </button>

      {creating && (
        <form className="rail-popover" onSubmit={(event) => void create(event)}>
          <label>
            New workspace
            <input
              type="text"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="acme"
              autoFocus
              required
            />
          </label>
          {error !== null && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          <button type="submit" className="primary">
            Create
          </button>
        </form>
      )}
    </nav>
  )
}
