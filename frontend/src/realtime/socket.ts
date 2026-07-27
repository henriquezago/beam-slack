import { Socket } from 'phoenix'
import { getAuthToken } from '../api/client'

/**
 * One socket per browser tab, shared by every channel the tab is viewing. This
 * mirrors the backend: one `UserSocket` process carrying many channel processes.
 */
let socket: Socket | null = null

export function getSocket(): Socket | null {
  if (getAuthToken() === null) return null

  if (socket === null) {
    socket = new Socket('/socket', {
      // Read the token lazily so a reconnect after re-login uses the new one.
      params: () => ({ token: getAuthToken() }),
    })
    socket.connect()
  }

  return socket
}

export function disconnectSocket(): void {
  socket?.disconnect()
  socket = null
}
