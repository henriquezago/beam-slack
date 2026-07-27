import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { api, getAuthToken, setAuthToken, type Credentials, type Registration } from '../api/client'
import type { User } from '../api/types'
import { disconnectSocket } from '../realtime/socket'
import { AuthContext, type AuthState } from './context'

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false

    const restore = async () => {
      if (getAuthToken() === null) {
        setLoading(false)
        return
      }

      try {
        const restored = await api.me()
        if (!cancelled) setUser(restored)
      } catch {
        // An expired or revoked token is indistinguishable from no token here.
        setAuthToken(null)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void restore()

    return () => {
      cancelled = true
    }
  }, [])

  const login = useCallback(async (credentials: Credentials) => {
    const session = await api.login(credentials)
    setAuthToken(session.token)
    setUser(session.user)
  }, [])

  const register = useCallback(async (registration: Registration) => {
    const session = await api.register(registration)
    setAuthToken(session.token)
    setUser(session.user)
  }, [])

  const logout = useCallback(() => {
    disconnectSocket()
    setAuthToken(null)
    setUser(null)
  }, [])

  const value = useMemo<AuthState>(
    () => ({ user, loading, login, register, logout }),
    [user, loading, login, register, logout],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
