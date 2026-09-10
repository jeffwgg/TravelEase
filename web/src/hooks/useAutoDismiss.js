import { useEffect, useRef } from 'react'

const AUTO_DISMISS_MS = 5000

/**
 * Clears an alert message state (error, success, ...) five seconds after it
 * is set, so stale alerts never linger on screen. The clear callback may
 * change between renders; only the message identity re-arms the timer.
 */
export function useAutoDismiss(message, clear) {
  const clearRef = useRef(clear)
  clearRef.current = clear

  useEffect(() => {
    if (!message) return undefined
    const timer = setTimeout(() => clearRef.current(), AUTO_DISMISS_MS)
    return () => clearTimeout(timer)
  }, [message])
}
