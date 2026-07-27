import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// Which backend node this dev server proxies to. Track 4 runs two nodes at once:
//
//   VITE_API_URL=http://127.0.0.1:4000 npm run dev -- --port 5173
//   VITE_API_URL=http://127.0.0.1:4001 npm run dev -- --port 5174
//
// Both browser sessions then talk to different BEAM nodes against the same
// database, which is the setup every cross-node observation needs.
const backend = process.env.VITE_API_URL ?? 'http://127.0.0.1:4000'
const backendWs = backend.replace(/^http/, 'ws')

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: Number(process.env.PORT ?? 5173),
    proxy: {
      '/api': backend,
      // The Phoenix socket needs an explicit WebSocket proxy entry.
      '/socket': { target: backendWs, ws: true },
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
  },
})
