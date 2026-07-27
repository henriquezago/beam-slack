import { useCallback, useEffect, useState } from 'react'
import { api } from '../api/client'
import type { Notification } from '../api/types'
import { getSocket } from '../realtime/socket'

/**
 * Loads notifications over HTTP and keeps them fresh via the `user:<id>` topic.
 */
export function useNotifications(userId: string | undefined) {
  const [notifications, setNotifications] = useState<Notification[]>([])
  const [unreadCount, setUnreadCount] = useState(0)
  const [open, setOpen] = useState(false)

  const reload = useCallback(async () => {
    if (userId === undefined) return

    const [list, unread] = await Promise.all([
      api.listNotifications(),
      api.unreadNotificationCount(),
    ])

    setNotifications(list)
    setUnreadCount(unread.count)
  }, [userId])

  useEffect(() => {
    void reload().catch(() => undefined)
  }, [reload])

  useEffect(() => {
    if (userId === undefined) return

    const socket = getSocket()
    if (socket === null) return

    const channel = socket.channel(`user:${userId}`, {})

    channel.on('notification', (payload) => {
      const notification = payload as Notification

      setNotifications((current) =>
        current.some((candidate) => candidate.id === notification.id)
          ? current
          : [notification, ...current],
      )
      setUnreadCount((count) => count + (notification.read_at === null ? 1 : 0))
    })

    channel.join()

    return () => {
      channel.leave()
    }
  }, [userId])

  const markRead = async (id: string) => {
    const updated = await api.markNotificationRead(id)

    setNotifications((current) =>
      current.map((candidate) => (candidate.id === id ? updated : candidate)),
    )
    setUnreadCount((count) => Math.max(0, count - 1))
  }

  const markAllRead = async () => {
    await api.markAllNotificationsRead()
    setNotifications((current) =>
      current.map((candidate) =>
        candidate.read_at === null
          ? { ...candidate, read_at: new Date().toISOString() }
          : candidate,
      ),
    )
    setUnreadCount(0)
  }

  return {
    notifications,
    unreadCount,
    open,
    setOpen,
    reload,
    markRead,
    markAllRead,
  }
}
