import { useState, type FormEvent } from 'react'
import { useAuth } from '../auth/useAuth'
import { describeError } from '../hooks/useAsync'
import { HealthBadge } from './HealthBadge'

type Mode = 'login' | 'register'

export function LoginScreen() {
  const { login, register } = useAuth()
  const [mode, setMode] = useState<Mode>('login')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('henrique@example.com')
  const [password, setPassword] = useState('password123')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)

    try {
      if (mode === 'login') {
        await login({ email, password })
      } else {
        await register({ name, email, password })
      }
    } catch (caught) {
      setError(describeError(caught))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-screen">
      <form className="auth-card" onSubmit={(event) => void submit(event)}>
        <p className="eyebrow">Track 1 · Product surface</p>
        <h1>BeamSlack</h1>
        <p className="intro">
          {mode === 'login'
            ? 'Sign in to a seeded account, or create a new one.'
            : 'Create an account. You will be signed in immediately.'}
        </p>

        {mode === 'register' && (
          <label>
            Name
            <input
              type="text"
              value={name}
              autoComplete="username"
              onChange={(event) => setName(event.target.value)}
              required
            />
          </label>
        )}

        <label>
          Email
          <input
            type="email"
            value={email}
            autoComplete="email"
            onChange={(event) => setEmail(event.target.value)}
            required
          />
        </label>

        <label>
          Password
          <input
            type="password"
            value={password}
            autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </label>

        {error !== null && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}

        <button type="submit" className="primary" disabled={submitting}>
          {submitting ? 'Working…' : mode === 'login' ? 'Sign in' : 'Create account'}
        </button>

        <button
          type="button"
          className="link"
          onClick={() => {
            setMode(mode === 'login' ? 'register' : 'login')
            setError(null)
          }}
        >
          {mode === 'login' ? 'Need an account?' : 'Already have an account?'}
        </button>

        <footer className="auth-card__footer">
          <HealthBadge />
          <span>Seeded password: password123</span>
        </footer>
      </form>
    </div>
  )
}
