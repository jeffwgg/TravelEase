import { supabase } from '../lib/supabase'

const fields = 'id, institution_id, auth_user_id, name, email, contact_number, role, status, active, created_at, updated_at'

function institutionIdFrom(staffContext) {
  const id = staffContext?.institution_id || staffContext?.institutions?.id
  if (!id) throw new Error('Your institution could not be identified. Please sign in again.')
  return id
}

async function invoke(action, body = {}) {
  const { data, error } = await supabase.functions.invoke('manage-institution-staff', {
    body: { action, ...body },
  })
  if (error) {
    let message = error.message
    try {
      const responseBody = await error.context?.json()
      if (responseBody?.error) message = responseBody.error
    } catch { /* keep the Functions client error */ }
    throw new Error(message || 'Unable to manage staff.')
  }
  if (data?.error) throw new Error(data.error)
  return data
}

async function withSosAvailability(staff, institutionId) {
  if (!staff.length) return staff
  const { data, error } = await supabase.from('sos_requests')
    .select('assigned_staff_id').eq('institution_id', institutionId)
    .in('status', ['assigned', 'en_route'])
    .in('assigned_staff_id', staff.map(member => member.id))
  if (error) throw error
  const assigned = new Set((data || []).map(request => request.assigned_staff_id))
  return staff.map(member => assigned.has(member.id) ? { ...member, status: 'assigned' } : member)
}

export const staffRepository = {
  subscribe(institutionId, callback, staffId = null) {
    const channel = supabase
      .channel(`staff-availability:${institutionId}:${staffId || 'manager'}`)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'institution_staff',
        filter: staffId ? `id=eq.${staffId}` : `institution_id=eq.${institutionId}`,
      }, callback)
      .subscribe()
    return () => supabase.removeChannel(channel)
  },
  async getOwn() {
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError) throw authError
    if (!user) throw new Error('Please sign in again.')
    const { data, error } = await supabase.from('institution_staff').select(fields)
      .eq('auth_user_id', user.id).eq('role', 'staff').eq('active', true).single()
    if (error) throw error
    return (await withSosAvailability([data], data.institution_id))[0]
  },
  async updateOwnName(name) {
    const { error } = await supabase.rpc('update_my_staff_name', { p_name: name.trim() })
    if (error) throw error
  },
  async list(staffContext) {
    const institutionId = institutionIdFrom(staffContext)
    const { data, error } = await supabase.from('institution_staff').select(fields)
      .eq('institution_id', institutionId).eq('role', 'staff')
      .order('active', { ascending: false }).order('name')
    if (error) throw error
    return withSosAvailability(data || [], institutionId)
  },
  create(staff) { return invoke('create', { staff }) },
  update(staffId, staff) { return invoke('update', { staffId, staff }) },
  setActive(staffId, active) { return invoke('set_active', { staffId, active }) },
  remove(staffId) { return invoke('delete', { staffId }) },
}
