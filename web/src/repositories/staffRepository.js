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

export const staffRepository = {
  async list(staffContext) {
    const institutionId = institutionIdFrom(staffContext)
    const { data, error } = await supabase.from('institution_staff').select(fields)
      .eq('institution_id', institutionId).eq('role', 'staff')
      .order('active', { ascending: false }).order('name')
    if (error) throw error
    return data || []
  },
  create(staff) { return invoke('create', { staff }) },
  update(staffId, staff) { return invoke('update', { staffId, staff }) },
  setActive(staffId, active) { return invoke('set_active', { staffId, active }) },
  remove(staffId) { return invoke('delete', { staffId }) },
}
