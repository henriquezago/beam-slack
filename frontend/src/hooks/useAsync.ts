import { useCallback, useEffect, useState, type Dispatch, type SetStateAction } from 'react'
import { ApiError } from '../api/client'

export function describeError(error: unknown): string {
  if (error instanceof ApiError) return error.detail
  if (error instanceof Error) return error.message
  return 'Something went wrong'
}

export interface AsyncState<T> {
  data: T | null
  loading: boolean
  error: string | null
  reload: () => void
  setData: Dispatch<SetStateAction<T | null>>
}

/**
 * Runs `load` and tracks its lifecycle. Pass `null` to represent "nothing to
 * load yet", for example before a channel has been selected.
 *
 * `load` must be memoized by the caller (`useCallback`), since it is the effect
 * dependency.
 */
export function useAsync<T>(load: (() => Promise<T>) | null): AsyncState<T> {
  const [data, setData] = useState<T | null>(null)
  const [loading, setLoading] = useState(load !== null)
  const [error, setError] = useState<string | null>(null)
  const [nonce, setNonce] = useState(0)

  useEffect(() => {
    if (load === null) {
      setData(null)
      setError(null)
      setLoading(false)
      return
    }

    let cancelled = false
    setLoading(true)
    setError(null)

    load()
      .then((result) => {
        if (!cancelled) setData(result)
      })
      .catch((caught: unknown) => {
        if (!cancelled) setError(describeError(caught))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
    }
  }, [load, nonce])

  const reload = useCallback(() => {
    setNonce((current) => current + 1)
  }, [])

  return { data, loading, error, reload, setData }
}
