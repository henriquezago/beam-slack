import { useOutletContext } from 'react-router-dom'
import type { Channel } from '../api/types'

export interface ShellContext {
  channels: Channel[]
  reloadChannels: () => void
}

export function useShell(): ShellContext {
  return useOutletContext<ShellContext>()
}
