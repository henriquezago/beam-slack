import { useCallback, useEffect, useState } from 'react'
import './App.css'

type HealthState = 'checking' | 'healthy' | 'unavailable'

function App() {
  const [health, setHealth] = useState<HealthState>('checking')

  const checkHealth = useCallback(async () => {
    setHealth('checking')

    try {
      const response = await fetch('/api/health')
      const body: unknown = await response.json()

      setHealth(
        response.ok &&
          typeof body === 'object' &&
          body !== null &&
          'status' in body &&
          body.status === 'ok'
          ? 'healthy'
          : 'unavailable',
      )
    } catch {
      setHealth('unavailable')
    }
  }, [])

  useEffect(() => {
    void checkHealth()
  }, [checkHealth])

  return (
    <main>
      <p className="eyebrow">Phase 0 · Foundation</p>
      <h1>BeamSlack</h1>
      <p className="intro">
        A Slack-like application for learning Elixir, OTP, and the BEAM.
      </p>

      <section className={`health-card health-card--${health}`} aria-live="polite">
        <span className="status-dot" aria-hidden="true" />
        <div>
          <h2>Backend health</h2>
          <p>
            {health === 'checking' && 'Checking the Phoenix API…'}
            {health === 'healthy' && 'Phoenix is responding normally.'}
            {health === 'unavailable' && 'The Phoenix API is unavailable.'}
          </p>
        </div>
        <button type="button" onClick={() => void checkHealth()} disabled={health === 'checking'}>
          Check again
        </button>
      </section>

      <p className="scope-note">
        Durable domain state comes next. This screen stores no application data.
      </p>
    </main>
  )
}

export default App
