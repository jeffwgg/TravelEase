import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { MessageSquare, X } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from './AuthContext'
import { shouldNotifyChatMessage } from '../lib/chatNotifications'

const NotificationContext = createContext(null)

// Synthesize a pleasant chime sound using Web Audio API (no external asset required)
function playNotificationChime() {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return
    const ctx = new AudioContextClass()
    const now = ctx.currentTime

    // First note
    const osc1 = ctx.createOscillator()
    const gain1 = ctx.createGain()
    osc1.type = 'sine'
    osc1.frequency.setValueAtTime(587.33, now) // D5
    gain1.gain.setValueAtTime(0.15, now)
    gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.3)
    osc1.connect(gain1)
    gain1.connect(ctx.destination)
    osc1.start(now)
    osc1.stop(now + 0.3)

    // Second higher note
    const osc2 = ctx.createOscillator()
    const gain2 = ctx.createGain()
    osc2.type = 'sine'
    osc2.frequency.setValueAtTime(880.0, now + 0.12) // A5
    gain2.gain.setValueAtTime(0.2, now + 0.12)
    gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.5)
    osc2.connect(gain2)
    gain2.connect(ctx.destination)
    osc2.start(now + 0.12)
    osc2.stop(now + 0.5)
  } catch (_) {
    // AudioContext blocked or not supported — non-critical
  }
}

export function NotificationProvider({ children }) {
  const navigate = useNavigate()
  const location = useLocation()
  const { staffContext } = useAuth()
  const [toasts, setToasts] = useState([])
  const [permission, setPermission] = useState(
    typeof window !== 'undefined' && 'Notification' in window ? Notification.permission : 'default'
  )

  const activeRequestIdRef = useRef(null)
  const staffContextRef = useRef(staffContext)
  const assignmentCacheRef = useRef(new Map())

  // Keep staffContext ref current and clear toasts/cache when role is not staff
  useEffect(() => {
    staffContextRef.current = staffContext
    if (!staffContext || staffContext.role !== 'staff') {
      setToasts([])
      assignmentCacheRef.current.clear()
    }
  }, [staffContext])

  // Track active request ID if currently on /chat page
  useEffect(() => {
    if (location.pathname !== '/chat') {
      activeRequestIdRef.current = null
    }
  }, [location.pathname])

  const requestBrowserPermission = useCallback(async () => {
    if (typeof window !== 'undefined' && 'Notification' in window) {
      try {
        const result = await Notification.requestPermission()
        setPermission(result)
        return result
      } catch (e) {
        console.error('Error requesting notification permission:', e)
      }
    }
    return 'denied'
  }, [])

  const removeToast = useCallback((id) => {
    setToasts((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const handleOpenChat = useCallback((requestId, toastId) => {
    if (toastId) removeToast(toastId)
    navigate('/chat', { state: { requestId } })
  }, [navigate, removeToast])

  const setActiveChatId = useCallback((id) => {
    activeRequestIdRef.current = id
  }, [])

  // Listen to assistance_chat_messages ONLY when logged in as staff
  useEffect(() => {
    if (staffContext?.role !== 'staff' || !staffContext?.staff?.id) {
      return
    }

    const currentStaffId = staffContext.staff.id

    const channel = supabase
      .channel(`web_chat_notifications_${currentStaffId}`)
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

          // Quick pre-checks
          if (msg.sender_type !== 'traveler' || !msg.request_id) return
          if (activeRequestIdRef.current === msg.request_id) return

          const currentContext = staffContextRef.current
          if (!currentContext || currentContext.role !== 'staff' || currentContext.staff?.id !== currentStaffId) {
            return
          }

          // Check assignment cache or query Supabase
          let assignedStaffId = null
          const cached = assignmentCacheRef.current.get(msg.request_id)
          if (cached && Date.now() - cached.timestamp < 30000 && cached.assigned_staff_id === currentStaffId) {
            assignedStaffId = cached.assigned_staff_id
          } else {
            try {
              const { data: request, error } = await supabase
                .from('assistance_requests')
                .select('assigned_staff_id')
                .eq('id', msg.request_id)
                .maybeSingle()

              if (error) {
                console.warn('[NotificationContext] Error querying request assignment:', error)
                return
              }
              assignedStaffId = request?.assigned_staff_id ?? null
              if (assignedStaffId === currentStaffId) {
                assignmentCacheRef.current.set(msg.request_id, {
                  assigned_staff_id: assignedStaffId,
                  timestamp: Date.now(),
                })
              }
            } catch (err) {
              console.warn('[NotificationContext] Failed to query request:', err)
              return
            }
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

          const senderName = msg.sender_name || 'Traveler'
          const content = msg.content || 'Sent a new message'
          const toastId = `${msg.request_id}-${Date.now()}`

          // 1. Play chime sound
          playNotificationChime()

          // 2. Add in-app floating toast
          setToasts((prev) => [
            {
              id: toastId,
              requestId: msg.request_id,
              senderName,
              content,
              timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
            },
            ...prev.slice(0, 4), // max 5 simultaneous toasts
          ])

          // Auto-remove toast after 7s
          setTimeout(() => {
            removeToast(toastId)
          }, 7000)

          // 3. Fire native browser notification if granted
          if (typeof window !== 'undefined' && 'Notification' in window && Notification.permission === 'granted') {
            try {
              const notification = new Notification(`💬 ${senderName}`, {
                body: content,
                icon: '/logo.png',
                tag: `chat-${msg.request_id}`,
              })

              notification.onclick = () => {
                window.focus()
                navigate('/chat', { state: { requestId: msg.request_id } })
                notification.close()
              }
            } catch (err) {
              console.warn('Native notification error:', err)
            }
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [staffContext?.role, staffContext?.staff?.id, navigate, removeToast])

  return (
    <NotificationContext.Provider value={{ toasts, removeToast, handleOpenChat, setActiveChatId, permission, requestBrowserPermission }}>
      {children}
      <ToastContainer toasts={toasts} onOpen={handleOpenChat} onClose={removeToast} />
    </NotificationContext.Provider>
  )
}

export function useNotifications() {
  const ctx = useContext(NotificationContext)
  if (!ctx) {
    throw new Error('useNotifications must be used within a NotificationProvider')
  }
  return ctx
}

function ToastContainer({ toasts, onOpen, onClose }) {
  if (!toasts || toasts.length === 0) return null

  return (
    <div
      style={{
        position: 'fixed',
        bottom: '24px',
        right: '24px',
        zIndex: 99999,
        display: 'flex',
        flexDirection: 'column-reverse',
        gap: '12px',
        maxWidth: '380px',
        width: 'calc(100vw - 48px)',
        pointerEvents: 'none',
      }}
    >
      {toasts.map((toast) => (
        <div
          key={toast.id}
          style={{
            pointerEvents: 'auto',
            background: 'var(--surface, #ffffff)',
            color: 'var(--text-primary, #0f172a)',
            borderRadius: '16px',
            border: '1.5px solid var(--primary, #3b82f6)',
            boxShadow: '0 20px 40px -10px rgba(0, 0, 0, 0.25), 0 0 15px rgba(59, 130, 246, 0.25)',
            padding: '16px',
            cursor: 'pointer',
            display: 'flex',
            gap: '12px',
            alignItems: 'flex-start',
            transition: 'all 0.2s ease',
          }}
          onClick={() => onOpen(toast.requestId, toast.id)}
        >
          {/* Avatar icon */}
          <div
            style={{
              width: '40px',
              height: '40px',
              borderRadius: '12px',
              background: 'rgba(59, 130, 246, 0.15)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
              color: 'var(--primary, #3b82f6)',
            }}
          >
            <MessageSquare size={20} />
          </div>

          {/* Content */}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2px' }}>
              <span style={{ fontSize: '13px', fontWeight: '700', color: 'var(--text-primary, #0f172a)' }}>
                {toast.senderName}
              </span>
              <span style={{ fontSize: '11px', color: 'var(--text-muted, #94a3b8)' }}>
                {toast.timestamp}
              </span>
            </div>
            <div
              style={{
                fontSize: '12px',
                color: 'var(--text-secondary, #475569)',
                lineHeight: '1.4',
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                marginBottom: '6px',
              }}
            >
              {toast.content}
            </div>
            <div
              style={{
                fontSize: '11px',
                fontWeight: '600',
                color: 'var(--primary, #3b82f6)',
                display: 'flex',
                alignItems: 'center',
                gap: '4px',
              }}
            >
              Click to open chat →
            </div>
          </div>

          {/* Close button */}
          <button
            onClick={(e) => {
              e.stopPropagation()
              onClose(toast.id)
            }}
            style={{
              background: 'transparent',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--text-muted, #94a3b8)',
              padding: '2px',
              borderRadius: '6px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
            title="Dismiss"
          >
            <X size={16} />
          </button>
        </div>
      ))}
    </div>
  )
}
