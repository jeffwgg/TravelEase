import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/AuthContext'
import { shouldNotifyChatMessage } from '../lib/chatNotifications'

/**
 * useChatNotifications
 *
 * Subscribes to new chat messages from travelers for assigned staff.
 * Shows a browser push notification when a traveler message arrives and
 * the staff member is NOT currently viewing that specific conversation.
 *
 * @param {string|null} activeRequestId - The request ID currently open in the chat panel.
 *                                        Notifications for this ID are suppressed.
 */
export function useChatNotifications(activeRequestId) {
  const navigate = useNavigate()
  const { staffContext } = useAuth()
  const navigateRef = useRef(navigate)
  const activeRequestIdRef = useRef(activeRequestId)
  const staffContextRef = useRef(staffContext)

  // Keep refs current without re-subscribing on every render
  useEffect(() => {
    navigateRef.current = navigate
  }, [navigate])
  useEffect(() => {
    activeRequestIdRef.current = activeRequestId
  }, [activeRequestId])
  useEffect(() => {
    staffContextRef.current = staffContext
  }, [staffContext])

  useEffect(() => {
    if (staffContext?.role !== 'staff' || !staffContext?.staff?.id) {
      return
    }

    const currentStaffId = staffContext.staff.id

    // Request permission once
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission()
    }

    const channel = supabase
      .channel(`web_chat_hook_${currentStaffId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'assistance_chat_messages',
        },
        async (payload) => {
          const msg = payload.new
          if (!msg) return
          if (msg.sender_type !== 'traveler' || !msg.request_id) return
          if (activeRequestIdRef.current === msg.request_id) return

          const currentContext = staffContextRef.current
          if (!currentContext || currentContext.role !== 'staff' || currentContext.staff?.id !== currentStaffId) {
            return
          }

          let assignedStaffId = null
          try {
            const { data: request } = await supabase
              .from('assistance_requests')
              .select('assigned_staff_id')
              .eq('id', msg.request_id)
              .maybeSingle()
            assignedStaffId = request?.assigned_staff_id ?? null
          } catch (e) {
            console.warn('[useChatNotifications] Failed to check request assignment:', e)
            return
          }

          const canNotify = shouldNotifyChatMessage({
            role: currentContext.role,
            currentStaffId,
            activeRequestId: activeRequestIdRef.current,
            messageSenderType: msg.sender_type,
            messageRequestId: msg.request_id,
            requestAssignedStaffId: assignedStaffId,
          })

          if (!canNotify) return
          if (!('Notification' in window) || Notification.permission !== 'granted') return

          const senderName = msg.sender_name || 'Traveler'
          const body = msg.content || ''

          const notification = new Notification(`💬 ${senderName}`, {
            body,
            icon: '/logo.png',
            badge: '/logo.png',
            tag: `chat-${msg.request_id}`,
          })

          notification.onclick = () => {
            window.focus()
            navigateRef.current('/chat', { state: { requestId: msg.request_id } })
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
  }, [staffContext?.role, staffContext?.staff?.id])
}
