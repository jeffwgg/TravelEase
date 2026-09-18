import React, { createContext, useContext, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { authRepository } from '../repositories/authRepository'
import { validatePortalContext } from '../lib/accountAccess'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [staffContext, setStaffContext] = useState(null)
  const [loading, setLoading] = useState(true)
  const [accessError, setAccessError] = useState('')
  const validation = useRef(0)
  const validatedUser = useRef(null)

  const loadStaffContext = async (nextSession) => {
    const version = ++validation.current
    if (!nextSession?.user) {
      validatedUser.current = null
      setSession(null)
      setStaffContext(null)
      return null
    }
    try {
      const context = validatePortalContext(await authRepository.getStaffContext(nextSession.user.id), nextSession.user.id)
      if (version === validation.current) {
        validatedUser.current = nextSession.user.id
        setSession(nextSession)
        setStaffContext(context)
        setAccessError('')
      }
      return context
    } catch (error) {
      if (version === validation.current) {
        validatedUser.current = null
        setSession(null)
        setStaffContext(null)
        setAccessError(error.message)
        await authRepository.signOut()
      }
      throw error
    }
  }

  useEffect(() => {
    let active = true
    let authEvent = 0

    const restoreSession = async () => {
      try {
        const { data, error } = await supabase.auth.getSession()
        if (error) throw error
        if (!active || authEvent !== 0) return
        await loadStaffContext(data.session)
      } catch (error) {
        console.error('Unable to load staff authorization:', error)
      } finally {
        if (active && authEvent === 0) setLoading(false)
      }
    }

    restoreSession()

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      const event = ++authEvent
      if (nextSession?.user?.id !== validatedUser.current) {
        setSession(null)
        setStaffContext(null)
        setLoading(true)
      }
      setTimeout(async () => {
        if (!active || event !== authEvent) return
        try {
          await loadStaffContext(nextSession)
        } catch (error) {
          console.error('Unable to refresh staff authorization:', error)
        } finally {
          if (active && event === authEvent) setLoading(false)
        }
      }, 0)
    })

    return () => {
      active = false
      validation.current++
      listener.subscription.unsubscribe()
    }
  }, [])

  const signIn = async (email, password) => {
    const { session: nextSession } = await authRepository.signIn(email, password)
    return loadStaffContext(nextSession)
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
    validatePortalContext(await authRepository.getStaffContext(session?.user?.id), session?.user?.id)
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
      accessError,
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
