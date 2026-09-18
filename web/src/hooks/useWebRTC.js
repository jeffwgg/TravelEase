import { useWebRTCContext } from '../context/WebRTCContext'

/**
 * useWebRTC — Web (Staff) hook
 *
 * Re-exports the global WebRTC context so calls can be initiated and received
 * seamlessly from any page across the web portal.
 */
export function useWebRTC() {
  const ctx = useWebRTCContext()
  return {
    ...ctx,
    subscribeToSignaling: () => () => {},
  }
}
