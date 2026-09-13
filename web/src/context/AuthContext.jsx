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

    const restoreSession = async () => {
      try {
        const { data, error } = await supabase.auth.getSession()
        if (error) throw error
        if (!active) return
        await loadStaffContext(data.session)
      } catch (error) {
        console.error('Unable to load staff authorization:', error)
        if (active) {
          setSession(null)
          setStaffContext(null)
        }
      } finally {
        if (active) setLoading(false)
      }
    }

    restoreSession()

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
    if (!context?.institutions) {
      await authRepository.signOut()
      throw new Error('This account is not an institution account.')
    }
    if (context.role === 'manager' && context.institutions.verification_status !== 'email_verified') {
      await authRepository.signOut()
      throw new Error('Verify your institution email before signing in.')
    }
    if (!context.institutions.active || (context.role === 'staff' && !context.staff?.active)) {
      await authRepository.signOut()
      throw new Error('This institution account is not active yet.')
    }
    return context
  }

  const registerInstitution = async (form) => {
    console.log('[InstitutionRegistration][AuthContext] Forwarding registration to repository', {
      formKeys: Object.keys(form),
      hasDocument: form.registrationDocument instanceof File,
    })
    try {
      const result = await authRepository.registerInstitution(form)
      console.log('[InstitutionRegistration][AuthContext] Repository registration resolved', result)
      return result
    } catch (error) {
      console.error('[InstitutionRegistration][AuthContext] Repository registration rejected', error)
      throw error
    }
  }

  const sendPasswordReset = (email) => authRepository.sendPasswordReset(email)

  const updatePassword = async (password) => {
    const result = await authRepository.updatePassword(password)
    await authRepository.signOut()
    setSession(null)
    setStaffContext(null)
    return result
  }

  const completeStaffSetup = async (password) => {
    const result = await authRepository.completeStaffSetup(password)
    await authRepository.signOut()
    setSession(null)
    setStaffContext(null)
    return result
  }

  const refreshStaffContext = () => loadStaffContext(session)

  const signOut = async () => {
    await authRepository.signOut()
    setSession(null)
    setStaffContext(null)
  }

  return (
    <AuthContext.Provider value={{
      session,
      staffContext,
      loading,
      signIn,
      signOut,
      registerInstitution,
      sendPasswordReset,
      updatePassword,
      completeStaffSetup,
      refreshStaffContext,
    }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used inside AuthProvider')
  return value
}
