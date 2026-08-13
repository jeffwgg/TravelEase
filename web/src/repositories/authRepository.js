import { supabase } from '../lib/supabase'

export const authRepository = {
  async signIn(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    return data
  },

  async signOut() {
    const { error } = await supabase.auth.signOut()
    if (error) throw error
  },

  async getStaffContext(userId) {
    const { data, error } = await supabase
      .from('institutions')
      .select('id, name, branch, active, account_user_id')
      .eq('account_user_id', userId)
      .eq('active', true)
      .maybeSingle()

    if (error) throw error
    if (!data) return null

    return { institution_id: data.id, institutions: data }
  },
}
