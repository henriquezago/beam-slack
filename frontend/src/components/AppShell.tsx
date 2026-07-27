import { useCallback, useEffect } from 'react'
import { Outlet, useNavigate, useParams } from 'react-router-dom'
import { api } from '../api/client'
import { useAsync } from '../hooks/useAsync'
import { ChannelSidebar } from './ChannelSidebar'
import { WorkspaceRail } from './WorkspaceRail'
import type { ShellContext } from './shellContext'

export function AppShell() {
  const { workspaceId } = useParams<{ workspaceId: string }>()
  const navigate = useNavigate()

  const workspaces = useAsync(useCallback(() => api.listWorkspaces(), []))

  const loadChannels = useCallback(
    () => (workspaceId === undefined ? Promise.resolve([]) : api.listChannels(workspaceId)),
    [workspaceId],
  )

  const channels = useAsync(workspaceId === undefined ? null : loadChannels)

  const workspace = workspaces.data?.find((candidate) => candidate.id === workspaceId) ?? null

  // A workspace the user does not belong to would render an empty shell whose
  // every request 403s. Send them home instead. The condition deliberately keys
  // off the membership list rather than a failed channel fetch, so a transient
  // API error does not bounce the user back and forth with HomeRedirect.
  const notAMember =
    workspaces.data !== null && workspaceId !== undefined && workspace === null

  useEffect(() => {
    if (notAMember) void navigate('/', { replace: true })
  }, [notAMember, navigate])

  const context: ShellContext = {
    channels: channels.data ?? [],
    reloadChannels: channels.reload,
  }

  return (
    <div className="app-shell">
      <WorkspaceRail
        workspaces={workspaces.data ?? []}
        activeWorkspaceId={workspaceId}
        onCreated={workspaces.reload}
      />
      <ChannelSidebar
        workspace={workspace}
        channels={channels.data ?? []}
        loading={channels.loading}
        error={channels.error}
        onChannelCreated={channels.reload}
      />
      <main className="app-main">
        <Outlet context={context} />
      </main>
    </div>
  )
}
