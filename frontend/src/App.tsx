import type { ReactNode } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { ChannelView } from './components/ChannelView'
import { HomeRedirect } from './components/HomeRedirect'
import { LoginScreen } from './components/LoginScreen'
import { useAuth } from './auth/useAuth'
import './App.css'

function RequireAuth({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth()

  if (loading) {
    return (
      <div className="auth-screen">
        <p className="muted">Restoring your session…</p>
      </div>
    )
  }

  if (user === null) return <Navigate to="/login" replace />

  return children
}

function LoginRoute() {
  const { user, loading } = useAuth()

  if (loading) {
    return (
      <div className="auth-screen">
        <p className="muted">Restoring your session…</p>
      </div>
    )
  }

  if (user !== null) return <Navigate to="/" replace />

  return <LoginScreen />
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginRoute />} />

      <Route
        path="/workspaces/:workspaceId"
        element={
          <RequireAuth>
            <AppShell />
          </RequireAuth>
        }
      >
        <Route index element={<ChannelView />} />
        <Route path="channels/:channelId" element={<ChannelView />} />
      </Route>

      <Route
        path="*"
        element={
          <RequireAuth>
            <HomeRedirect />
          </RequireAuth>
        }
      />
    </Routes>
  )
}
