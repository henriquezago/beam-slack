import { useCallback, useEffect, useState } from 'react'
import { api, type Health } from '../api/client'

type HealthState = 'checking' | 'healthy' | 'unavailable'

const LABELS: Record<HealthState, string> = {
  checking: 'Checking the Phoenix API…',
  healthy: 'Phoenix is responding normally.',
  unavailable: 'The Phoenix API is unavailable.',
}

/** "beamslack_a@DESKTOP" is more than anyone needs to read in a sidebar. */
function shortNode(node: string): string {
  return node.split('@')[0].replace(/^beamslack_?/, '') || node
}

/**
 * Kept from Phase 0. It is the cheapest possible answer to "is the BEAM node
 * still there", which matters once the fault-injection labs start killing things.
 *
 * From Track 4 it answers a second question: *which* node. Two browser sessions
 * pointed at two nodes look identical otherwise, and every cross-node observation
 * depends on telling them apart.
 */
export function HealthBadge() {
  const [state, setState] = useState<HealthState>('checking')
  const [health, setHealth] = useState<Health>({ up: false })

  const check = useCallback(async () => {
    setState('checking')
    const result = await api.health()
    setHealth(result)
    setState(result.up ? 'healthy' : 'unavailable')
  }, [])

  useEffect(() => {
    void check()
    const interval = setInterval(() => void check(), 15_000)
    return () => clearInterval(interval)
  }, [check])

  const peers = health.connectedNodes ?? []

  const title = health.node
    ? `${LABELS[state]}\nNode: ${health.node}\n${
        peers.length > 0 ? `Connected to: ${peers.join(', ')}` : 'No other nodes connected.'
      }`
    : LABELS[state]

  return (
    <button
      type="button"
      className={`health-badge health-badge--${state}`}
      onClick={() => void check()}
      title={title}
      aria-label={title}
    >
      <span className="status-dot" aria-hidden="true" />
      <span className="health-badge__text">
        {state === 'healthy' ? 'API up' : state === 'checking' ? 'Checking' : 'API down'}
      </span>
      {state === 'healthy' && health.node && (
        <span className="health-badge__node">
          {shortNode(health.node)}
          {peers.length > 0 && <span className="health-badge__peers">+{peers.length}</span>}
        </span>
      )}
    </button>
  )
}
