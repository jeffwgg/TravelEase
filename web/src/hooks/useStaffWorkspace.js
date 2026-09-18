import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { staffRepository } from '../repositories/staffRepository'
import { sosRequestRepository } from '../repositories/sosRequestRepository'

export default function useStaffWorkspace() {
  const { staffContext } = useAuth()
  const institutionId = staffContext?.institution_id
  const staffId = staffContext?.role === 'staff' ? staffContext.staff?.id : null
  const [data, setData] = useState({ tasks: [], staff: null, loading: true, error: '' })
  const [revision, setRevision] = useState(0)
  const refresh = useCallback(() => setRevision(value => value + 1), [])
  useEffect(() => {
    let active = true
    if (!staffId || !institutionId) {
      setData({ tasks: [], staff: null, loading: false, error: 'Staff access is required.' })
      return undefined
    }
    const load = async () => {
      try {
        const [tasks, staff] = await Promise.all([
          sosRequestRepository.listForInstitution(institutionId, staffId), staffRepository.getOwn(),
        ])
        if (active) setData({ tasks: tasks.filter(task => task.assigned_staff_id === staffId), staff, loading: false, error: '' })
      } catch (error) {
        if (active) setData(previous => ({ ...previous, loading: false, error: error.message || 'Unable to refresh your tasks.' }))
      }
    }
    load()
    const unsubscribe = sosRequestRepository.subscribe(institutionId, load, staffId)
    const timer = window.setInterval(load, 10000)
    return () => { active = false; unsubscribe(); window.clearInterval(timer) }
  }, [staffId, institutionId, revision])
  return { ...data, refresh }
}
