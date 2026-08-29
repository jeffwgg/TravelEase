import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

/**
 * useChatNotifications
 *
 * Subscribes globally to new chat messages from travelers.
 * Shows a browser push notification when a traveler message arrives and
 * the staff member is NOT currently viewing that specific conversation.
 *
 * @param {string|null} activeRequestId - The request ID currently open in the chat panel.
 *                                        Notifications for this ID are suppressed.
 */
export function useChatNotifications(activeRequestId) {
  const navigate = useNavigate()
  const navigateRef = useRef(navigate)
  const activeRequestIdRef = useRef(activeRequestId)

  // Keep refs current without re-subscribing on every render
  useEffect(() => {
    navigateRef.current = navigate
  }, [navigate])
  useEffect(() => {
    activeRequestIdRef.current = activeRequestId
  }, [activeRequestId])

  useEffect(() => {
    // Request permission once
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission()
    }

    const channel = supabase
      .channel('web_global_chat_notifications')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'assistance_chat_messages',
        },
        (payload) => {
          const msg = payload.new
          if (!msg) return

          // Staff portal only cares about traveler messages
          if (msg.sender_type !== 'traveler') return

          const requestId = msg.request_id
          if (!requestId) return

          // Suppress if staff is already viewing this conversation
          if (activeRequestIdRef.current === requestId) return

          // Only show if permission granted
          if (!('Notification' in window) || Notification.permission !== 'granted') return

          const senderName = msg.sender_name || 'Traveler'
          const body = msg.content || ''

          const notification = new Notification(`💬 ${senderName}`, {
            body,
            icon: '/logo.png',
            badge: '/logo.png',
            tag: `chat-${requestId}`, // Replaces previous notification for same chat
          })

          notification.onclick = () => {
            window.focus()
            navigateRef.current('/chat', { state: { requestId } })
            notification.close()
          }

          // Auto-dismiss after 8 seconds
          setTimeout(() => notification.close(), 8000)
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, []) // Only mount/unmount once — refs keep values current
}
