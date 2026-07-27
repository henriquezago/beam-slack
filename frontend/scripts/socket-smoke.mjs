// Manual end-to-end check of the WebSocket path against a running backend:
//
//     cd frontend && node scripts/socket-smoke.mjs
//
// Requires `mix phx.server` on port 4000 and a seeded database.
import { Socket } from 'phoenix'

const API = 'http://127.0.0.1:4000'

async function json(path, options = {}) {
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: { accept: 'application/json', 'content-type': 'application/json', ...options.headers },
  })

  if (!response.ok) throw new Error(`${options.method ?? 'GET'} ${path} -> ${response.status}`)

  return (await response.json()).data
}

const { token } = await json('/api/session', {
  method: 'POST',
  body: JSON.stringify({ email: 'henrique@example.com', password: 'password123' }),
})

const auth = { authorization: `Bearer ${token}` }
const [workspace] = await json('/api/workspaces', { headers: auth })
const channels = await json(`/api/workspaces/${workspace.id}/channels`, { headers: auth })
const general = channels.find((channel) => channel.name === 'general')

console.log(`workspace ${workspace.name}, channel #${general.name}`)

const socket = new Socket(`ws://127.0.0.1:4000/socket`, { params: { token } })

socket.onError((error) => console.log('socket error:', error?.message ?? error))
socket.connect()

const channel = socket.channel(`channel:${general.id}`, {})

const joined = await new Promise((resolve, reject) => {
  channel
    .join()
    .receive('ok', resolve)
    .receive('error', reject)
    .receive('timeout', () => reject(new Error('join timed out')))
})

console.log('joined:', joined)

const push = await new Promise((resolve) => {
  channel
    .push('new_message', { body: 'from the socket smoke test' }, 2000)
    .receive('ok', (message) => resolve(`ok: ${message.body}`))
    .receive('error', (reason) => resolve(`error: ${JSON.stringify(reason)}`))
    .receive('timeout', () => resolve('timeout (expected until Lab 02 is implemented)'))
})

console.log('new_message push:', push)

const rejected = await new Promise((resolve) => {
  const anonymous = new Socket('ws://127.0.0.1:4000/socket', { params: { token: 'bogus' } })
  anonymous.onError(() => resolve('connection refused (expected)'))
  anonymous.onOpen(() => resolve('connection accepted (NOT expected)'))
  anonymous.connect()
  setTimeout(() => resolve('no verdict'), 2000)
})

console.log('bogus token:', rejected)

process.exit(0)
