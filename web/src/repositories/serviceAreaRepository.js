import { supabase } from '../lib/supabase'

const fields = 'id, institution_id, name, address, latitude, longitude, radius_m, active, created_at, updated_at'

function institutionIdFrom(staffContext) {
  const id = staffContext?.institution_id || staffContext?.institutions?.id
  if (!id) throw new Error('Your institution could not be identified. Please sign in again.')
  return id
}

export const serviceAreaRepository = {
  async list(staffContext) {
    const institutionId = institutionIdFrom(staffContext)
    const { data, error } = await supabase.from('service_areas').select(fields)
      .eq('institution_id', institutionId).order('created_at')
    if (error) throw error
    return data || []
  },

  async save(staffContext, values) {
    const institutionId = institutionIdFrom(staffContext)
    const payload = {
      institution_id: institutionId,
      name: values.name.trim(),
      address: values.address.trim() || null,
      latitude: Number(values.latitude),
      longitude: Number(values.longitude),
      radius_m: Number(values.radius_m),
      active: Boolean(values.active),
    }
    const normalizeName = name => name.trim().replace(/\s+/g, ' ').toLowerCase()
    const sameCoordinate = (a, b) => Number(a).toFixed(6) === Number(b).toFixed(6)
    const existing = await this.list(staffContext)
    const duplicate = existing.some(area => area.id !== values.id && (
      normalizeName(area.name) === normalizeName(payload.name)
      || (sameCoordinate(area.latitude, payload.latitude)
        && sameCoordinate(area.longitude, payload.longitude)
        && Number(area.radius_m) === payload.radius_m)
    ))
    if (duplicate) throw new Error('This service area already exists. Edit the existing area instead of creating another one.')
    let query = values.id
      ? supabase.from('service_areas').update(payload).eq('id', values.id).eq('institution_id', institutionId)
      : supabase.from('service_areas').insert(payload)
    const { data, error } = await query.select(fields).single()
    if (error?.code === '23505') {
      throw new Error('This service area already exists. Edit the existing area instead of creating another one.')
    }
    if (error) throw error
    return data
  },

  async setActive(staffContext, area, active) {
    return this.save(staffContext, { ...area, active })
  },

  async remove(staffContext, id) {
    const institutionId = institutionIdFrom(staffContext)
    const { error } = await supabase.from('service_areas').delete()
      .eq('id', id).eq('institution_id', institutionId)
    if (error?.code === '23503') {
      const reference = [error.message, error.details].filter(Boolean).join(' ').toLowerCase()
      if (reference.includes('sos_requests')) {
        throw new Error('This service area cannot be deleted because it is linked to an SOS request. Deactivate it instead to preserve the request history.')
      }
      throw new Error('This service area cannot be deleted because it is used by existing records. Deactivate it instead to preserve their history.')
    }
    if (error) throw new Error('Unable to delete this service area. Please try again.')
  },
}
