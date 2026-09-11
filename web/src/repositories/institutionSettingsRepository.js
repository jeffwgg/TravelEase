import { supabase } from '../lib/supabase'

const profileSelect = [
  'id',
  'account_user_id',
  'name',
  'institution_type',
  'official_contact',
  'service_address',
  'active',
  'verification_status',
  'registration_document_path',
  'created_at',
  'updated_at',
].join(', ')

async function requireCurrentUser() {
  const { data, error } = await supabase.auth.getUser()
  if (error) throw error
  if (!data.user) throw new Error('Your session has expired. Please sign in again.')
  return data.user
}

export const institutionSettingsRepository = {
  async getCurrentInstitution() {
    const user = await requireCurrentUser()
    const { data, error } = await supabase
      .from('institutions')
      .select(profileSelect)
      .eq('account_user_id', user.id)
      .single()

    if (error) throw error
    return data
  },

  async updateCurrentInstitution(values) {
    const user = await requireCurrentUser()
    const payload = {
      name: values.name.trim(),
      institution_type: values.institution_type,
      official_contact: values.official_contact.trim(),
      service_address: values.service_address.trim(),
    }

    const { data, error } = await supabase
      .from('institutions')
      .update(payload)
      .eq('account_user_id', user.id)
      .select(profileSelect)
      .single()

    if (error) throw error
    return data
  },
}
