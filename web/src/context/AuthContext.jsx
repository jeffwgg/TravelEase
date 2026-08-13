import React, { createContext, useContext, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { authRepository } from '../repositories/authRepository'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [staffContext, setStaffContext] = useState(null)
  const [loading, setLoading] = useState(true)

  const loadStaffContext = async (nextSession) => {
    setSession(nextSession)
    if (!nextSession?.user) {
      setStaffContext(null)
      return null
    }

    const context = await authRepository.getStaffContext(nextSession.user.id)
    setStaffContext(context)
    return context
  }

  useEffect(() => {
    let active = true

    supabase.auth.getSession().then(async ({ data }) => {
      if (!active) return
      try {
        await loadStaffContext(data.session)
      } catch (error) {
        console.error('Unable to load staff authorization:', error)
        setStaffContext(null)
      } finally {
        if (active) setLoading(false)
      }
    })

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setTimeout(async () => {
        if (!active) return
        try {
          await loadStaffContext(nextSession)
        } catch (error) {
          console.error('Unable to refresh staff authorization:', error)
          setStaffContext(null)
        } finally {
          if (active) setLoading(false)
        }
      }, 0)
    })

    return () => {
      active = false
      listener.subscription.unsubscribe()
    }
  }, [])

  const signIn = async (email, password) => {
    const { session: nextSession } = await authRepository.signIn(email, password)
    const context = await loadStaffContext(nextSession)
    if (!context?.institutions?.active) {
      await authRepository.signOut()
      throw new Error('This account is not linked to an active institution.')
    }
    return context
  }

  const signOut = async () => {
    await authRepository.signOut()
    setSession(null)
    setStaffContext(null)
  }

  return <AuthContext.Provider value={{ session, staffContext, loading, signIn, signOut }}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used inside AuthProvider')
  return value
}
