import { createContext } from 'react'
import type { Credentials, Registration } from '../api/client'
import type { User } from '../api/types'

export interface AuthState {
  user: User | null
  /** True until the stored token has been checked against the backend. */
  loading: boolean
  login: (credentials: Credentials) => Promise<void>
  register: (registration: Registration) => Promise<void>
  logout: () => void
}

export const AuthContext = createContext<AuthState | null>(null)
